import Darwin
import Foundation
import VaultyCore

private enum CLIError: Error, LocalizedError {
    case missingValue(option: String)
    case emptyValue(option: String)
    case unknownCommand(String)
    case unknownArgument(String)
    case invalidOption(command: String, option: String)

    var errorDescription: String? {
        switch self {
        case let .missingValue(option):
            return "Missing value for \(option)."
        case let .emptyValue(option):
            return "The value for \(option) cannot be empty."
        case let .unknownCommand(command):
            return "Unknown command: \(command). Run 'vaulty help' for usage."
        case let .unknownArgument(argument):
            return "Unknown argument: \(argument). Run 'vaulty help' for usage."
        case let .invalidOption(command, option):
            return "\(option) cannot be used with \(command)."
        }
    }
}

private enum Command {
    case block
    case unblock
    case status
    case shortFormBlock
    case shortFormUnblock
    case shortFormStatus
    case allowlist
    case help
    case version
}

private struct Arguments {
    let command: Command
    let hostsFileURL: URL
    let domains: [String]
    let dryRun: Bool
}

@main
private struct VaultyCLI {
    private static var executableName: String {
        let name = URL(fileURLWithPath: CommandLine.arguments.first ?? "vaulty").lastPathComponent
        return name == "focusvault" || name == "focusvault-cli" ? "focusvault" : "vaulty"
    }

    static func main() {
        let executable = URL(fileURLWithPath: CommandLine.arguments.first ?? "vaulty").lastPathComponent
        if executable.hasSuffix("native-host") {
            Darwin.exit(VaultyNativeMessagingHost.run())
        }

        let rawArguments = Array(CommandLine.arguments.dropFirst())
        do {
            if try runInternalCommandIfNeeded(rawArguments) {
                return
            }
            let arguments = try parse(rawArguments)
            try run(arguments)
        } catch {
            let message = "error: \(error.localizedDescription)\n"
            FileHandle.standardError.write(Data(message.utf8))
            Darwin.exit(EXIT_FAILURE)
        }
    }

    private static func runInternalCommandIfNeeded(_ arguments: [String]) throws -> Bool {
        guard let command = arguments.first else { return false }

        if command == "guard" {
            guard arguments.count > 1 else {
                throw CLIError.unknownCommand("guard")
            }
            switch arguments[1].lowercased() {
            case "status":
                let installed = FileManager.default.isExecutableFile(atPath: YouTubeGuardPaths.helperPath)
                    && FileManager.default.fileExists(atPath: YouTubeGuardPaths.launchDaemonPath)
                let state = YouTubeGuardStorage().readState()
                print(installed ? "installed" : "not installed")
                print(state.isUnlocked(at: Date())
                    ? "YouTube open for \(state.remainingSeconds(at: Date())) more seconds"
                    : "YouTube locked")
            case "uninstall":
                let home = guardUserHome(arguments)
                try VaultyGuardInstaller.uninstall(userHome: home)
                print("Vaulty guard removed and the YouTube managed block opened.")
            default:
                throw CLIError.unknownCommand("guard \(arguments[1])")
            }
            return true
        }

        guard command.hasPrefix("internal-") else {
            return false
        }

        switch command {
        case "internal-guard-daemon":
            try VaultyGuardDaemon.run()
        case "internal-install-guard":
            let home = try internalValue("--user-home", in: arguments)
            let uidValue = try internalInteger("--uid", in: arguments)
            let gidValue = try internalInteger("--gid", in: arguments)
            try VaultyGuardInstaller.install(
                userHome: URL(fileURLWithPath: home, isDirectory: true),
                uid: uid_t(uidValue),
                gid: gid_t(gidValue)
            )
            print("Vaulty guard installed. Locking is now password-free; unlocking requires administrator approval and a chosen task.")
        case "internal-uninstall-guard":
            let home = try internalValue("--user-home", in: arguments)
            try VaultyGuardInstaller.uninstall(userHome: URL(fileURLWithPath: home, isDirectory: true))
            print("Vaulty guard removed and the YouTube managed block opened.")
        case "internal-native-host":
            Darwin.exit(VaultyNativeMessagingHost.run())
        case "internal-verify-guard-config":
            try VaultyGuardInstaller.verifyRenderedConfiguration()
            print("PASS: Vaulty guard daemon, authorization right, and native-host manifests are valid")
        case "internal-admin-unlock-request":
            guard geteuid() == 0 else {
                throw YouTubeGuardError.unavailable("Administrator permission is required to unlock YouTube.")
            }
            let home = try internalValue("--user-home", in: arguments)
            let uidValue = try internalInteger("--uid", in: arguments)
            let gidValue = try internalInteger("--gid", in: arguments)
            try VaultyGuardInstaller.installIfNeeded(
                userHome: URL(fileURLWithPath: home, isDirectory: true),
                uid: uid_t(uidValue),
                gid: gid_t(gidValue)
            )

            let storage = YouTubeGuardStorage()
            let request = YouTubeGuardRequest(
                command: .unlock,
                authorization: YouTubeGuardPaths.rootAuthorizedRequestMarker
            )
            storage.removeResponse(for: request.id)
            let requestURL = try storage.writeRequest(request)
            defer {
                try? FileManager.default.removeItem(at: requestURL)
                storage.removeResponse(for: request.id)
            }

            let deadline = Date().addingTimeInterval(12)
            var response: YouTubeGuardResponse?
            while Date() < deadline {
                if let current = storage.readResponse(for: request.id) {
                    response = current
                    break
                }
                Thread.sleep(forTimeInterval: 0.08)
            }
            guard let response else {
                throw YouTubeGuardError.unavailable("Vaulty’s guard did not answer. YouTube stayed locked.")
            }
            guard response.succeeded else {
                throw YouTubeGuardError.unavailable(response.message)
            }
            print("YouTube opened for 45 minutes.")
        case "internal-admin-test-unlock":
            guard geteuid() == 0 else {
                throw YouTubeGuardError.unavailable("Administrator permission is required for the test unlock.")
            }
            let storage = YouTubeGuardStorage()
            let engine = try YouTubeGuardEngine(
                storage: storage,
                authorizationValidator: { _ in true }
            )
            let request = YouTubeGuardRequest(
                command: .unlock,
                authorization: "administrator-test-unlock"
            )
            let response = try engine.process(request)
            storage.removeResponse(for: request.id)
            guard response.succeeded else {
                throw YouTubeGuardError.unavailable(response.message)
            }
            print("YouTube opened for a 45-minute administrator test session.")
        default:
            throw CLIError.unknownCommand(command)
        }
        return true
    }

    private static func internalValue(_ option: String, in arguments: [String]) throws -> String {
        guard let index = arguments.firstIndex(of: option), index + 1 < arguments.count else {
            throw CLIError.missingValue(option: option)
        }
        let value = arguments[index + 1]
        guard !value.isEmpty else { throw CLIError.emptyValue(option: option) }
        return value
    }

    private static func internalInteger(_ option: String, in arguments: [String]) throws -> UInt32 {
        let value = try internalValue(option, in: arguments)
        guard let number = UInt32(value) else {
            throw CLIError.unknownArgument("\(option) \(value)")
        }
        return number
    }

    private static func guardUserHome(_ arguments: [String]) -> URL {
        if let index = arguments.firstIndex(of: "--user-home"), index + 1 < arguments.count {
            return URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
        }
        if let sudoUser = ProcessInfo.processInfo.environment["SUDO_USER"],
           sudoUser != "root",
           let home = NSHomeDirectoryForUser(sudoUser) {
            return URL(fileURLWithPath: home, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    private static func parse(_ rawArguments: [String]) throws -> Arguments {
        guard let commandName = rawArguments.first else {
            return helpArguments()
        }

        let command: Command
        var commandArgumentEnd = 1
        switch commandName.lowercased() {
        case "block":
            command = .block
        case "unblock", "un-block":
            command = .unblock
        case "status":
            command = .status
        case "short-form-block", "shortform-block", "shorts-block":
            command = .shortFormBlock
        case "short-form-unblock", "shortform-unblock", "shorts-unblock":
            command = .shortFormUnblock
        case "short-form-status", "shortform-status", "shorts-status":
            command = .shortFormStatus
        case "short-form", "shortform":
            guard rawArguments.count > 1 else {
                throw CLIError.unknownCommand(commandName)
            }
            switch rawArguments[1].lowercased() {
            case "block":
                command = .shortFormBlock
            case "unblock", "un-block":
                command = .shortFormUnblock
            case "status":
                command = .shortFormStatus
            case "help", "--help", "-h":
                return helpArguments()
            default:
                throw CLIError.unknownCommand("\(commandName) \(rawArguments[1])")
            }
            commandArgumentEnd = 2
        case "allowlist", "channels":
            command = .allowlist
        case "help", "--help", "-h":
            return helpArguments()
        case "version", "--version", "-v":
            return Arguments(
                command: .version,
                hostsFileURL: FocusVaultBlocker.defaultHostsFileURL,
                domains: FocusVaultBlocker.defaultDomains,
                dryRun: false
            )
        default:
            throw CLIError.unknownCommand(commandName)
        }

        var hostsFileURL = FocusVaultBlocker.defaultHostsFileURL
        var customDomains: [String] = []
        var dryRun = false
        var index = commandArgumentEnd

        while index < rawArguments.count {
            let argument = rawArguments[index]
            switch argument {
            case "--hosts-file":
                guard index + 1 < rawArguments.count else {
                    throw CLIError.missingValue(option: argument)
                }
                let path = rawArguments[index + 1]
                guard !path.isEmpty else {
                    throw CLIError.emptyValue(option: argument)
                }
                hostsFileURL = URL(fileURLWithPath: path)
                index += 2
            case "--domain":
                guard command == .block else {
                    throw CLIError.invalidOption(command: commandName, option: argument)
                }
                guard index + 1 < rawArguments.count else {
                    throw CLIError.missingValue(option: argument)
                }
                let domain = rawArguments[index + 1]
                guard !domain.isEmpty else {
                    throw CLIError.emptyValue(option: argument)
                }
                customDomains.append(domain)
                index += 2
            case "--dry-run":
                guard command == .block else {
                    throw CLIError.invalidOption(command: commandName, option: argument)
                }
                dryRun = true
                index += 1
            case "--help", "-h":
                return helpArguments()
            default:
                throw CLIError.unknownArgument(argument)
            }
        }

        return Arguments(
            command: command,
            hostsFileURL: hostsFileURL,
            domains: customDomains.isEmpty ? FocusVaultBlocker.defaultDomains : customDomains,
            dryRun: dryRun
        )
    }

    private static func helpArguments() -> Arguments {
        Arguments(
            command: .help,
            hostsFileURL: FocusVaultBlocker.defaultHostsFileURL,
            domains: FocusVaultBlocker.defaultDomains,
            dryRun: false
        )
    }

    private static func run(_ arguments: Arguments) throws {
        switch arguments.command {
        case .help:
            printUsage()
        case .version:
            print("\(executableName) \(FocusVaultBlocker.version)")
        case .block:
            let blocker = try FocusVaultBlocker(
                hostsFileURL: arguments.hostsFileURL,
                domains: arguments.domains
            )
            if arguments.dryRun {
                print("Would add this managed section to \(arguments.hostsFileURL.path):")
                print(blocker.managedBlock)
                return
            }

            let changed = try blocker.block()
            if changed {
                print("YouTube vault engaged — blocked \(blocker.domains.joined(separator: ", ")).")
            } else {
                print("YouTube vault already engaged — nothing changed.")
            }
        case .unblock:
            let blocker = try FocusVaultBlocker(hostsFileURL: arguments.hostsFileURL)
            let changed = try blocker.unblock()
            print(changed ? "YouTube vault opened — removed its managed section." : "YouTube vault already open — nothing changed.")
        case .status:
            let blocker = try FocusVaultBlocker(hostsFileURL: arguments.hostsFileURL)
            let blocked = try blocker.isBlocked()
            print(blocked ? "blocked" : "unblocked")
            print("Vaulty YouTube hosts file: \(arguments.hostsFileURL.path)")
        case .shortFormBlock:
            let blocker = try ShortFormBlocker(hostsFileURL: arguments.hostsFileURL)
            let changed = try blocker.block()
            print(changed ? "Short-form vault engaged — blocked \(blocker.domains.joined(separator: ", "))." : "Short-form vault already engaged — nothing changed.")
        case .shortFormUnblock:
            let blocker = try ShortFormBlocker(hostsFileURL: arguments.hostsFileURL)
            let changed = try blocker.unblock()
            print(changed ? "Short-form vault opened — removed its managed section." : "Short-form vault already open — nothing changed.")
        case .shortFormStatus:
            let blocker = try ShortFormBlocker(hostsFileURL: arguments.hostsFileURL)
            let blocked = try blocker.isBlocked()
            print(blocked ? "blocked" : "unblocked")
            print("Vaulty short-form hosts file: \(arguments.hostsFileURL.path)")
        case .allowlist:
            print("Vaulty YouTube channel vault defaults:")
            for channel in YouTubeChannelDefaults.channels {
                print("- \(channel.name) \(channel.displayHandle) [\(channel.channelID)]")
            }
            print("Use the BrowserExtension mode to allow these channels while blocking other YouTube pages.")
        }
    }

    private static func printUsage() {
        print(
            """
            Vaulty — a free macOS website blocker
            Vault in. Get work done.

            Short commands:
              block      Engage the YouTube blocker.
              unblock    Open the YouTube blocker.
              status     Show whether the YouTube blocker is engaged.
              short-form Engage the separate short-form blocker.
              guard       Inspect or remove the installed automatic lock guard.
              allowlist   Show the fallback YouTube channels used before native pairing.
              version    Print the installed version.

            Usage:
              vaulty block [--domain DOMAIN ...] [--hosts-file PATH] [--dry-run]
              vaulty unblock [--hosts-file PATH]
              vaulty status [--hosts-file PATH]
              vaulty short-form block [--hosts-file PATH]
              vaulty short-form unblock [--hosts-file PATH]
              vaulty short-form status [--hosts-file PATH]
              vaulty guard status
              sudo vaulty guard uninstall [--user-home /Users/name]
              vaulty allowlist
              vaulty version

            The YouTube blocker manages its own marked section in /etc/hosts.
            The separate short-form blocker manages a second independent section and
            covers TikTok, Instagram, YouTube, and Facebook hosts completely; the
            browser companion adds path-level Reels/Shorts filtering when needed.
            Editing /etc/hosts normally requires sudo:

              sudo vaulty block
              vaulty status
              sudo vaulty unblock
              sudo vaulty short-form block
              vaulty short-form status
              sudo vaulty short-form unblock

            The legacy `focusvault` command remains a compatibility alias.
            --hosts-file is intended for safe testing or a separate hosts file.
            """
        )
    }
}
