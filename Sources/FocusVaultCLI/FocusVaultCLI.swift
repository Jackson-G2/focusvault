import Darwin
import Foundation
import FocusVaultCore

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
            return "Unknown command: \(command). Run 'focusvault help' for usage."
        case let .unknownArgument(argument):
            return "Unknown argument: \(argument). Run 'focusvault help' for usage."
        case let .invalidOption(command, option):
            return "\(option) cannot be used with \(command)."
        }
    }
}

private enum Command {
    case block
    case unblock
    case status
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
private struct FocusVaultCLI {
    static func main() {
        do {
            let arguments = try parse(Array(CommandLine.arguments.dropFirst()))
            try run(arguments)
        } catch {
            let message = "error: \(error.localizedDescription)\n"
            FileHandle.standardError.write(Data(message.utf8))
            Darwin.exit(EXIT_FAILURE)
        }
    }

    private static func parse(_ rawArguments: [String]) throws -> Arguments {
        guard let commandName = rawArguments.first else {
            return helpArguments()
        }

        let command: Command
        switch commandName.lowercased() {
        case "block":
            command = .block
        case "unblock", "un-block":
            command = .unblock
        case "status":
            command = .status
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
        var index = 1

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
            print("focusvault \(FocusVaultBlocker.version)")
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
                print("Vault engaged — blocked \(blocker.domains.joined(separator: ", ")).")
            } else {
                print("Vault already engaged — nothing changed.")
            }
        case .unblock:
            let blocker = try FocusVaultBlocker(
                hostsFileURL: arguments.hostsFileURL,
                domains: FocusVaultBlocker.defaultDomains
            )
            let changed = try blocker.unblock()
            print(changed ? "Vault opened — removed FocusVault's managed section." : "Vault already open — nothing changed.")
        case .status:
            let blocker = try FocusVaultBlocker(
                hostsFileURL: arguments.hostsFileURL,
                domains: FocusVaultBlocker.defaultDomains
            )
            let blocked = try blocker.isBlocked()
            print(blocked ? "blocked" : "unblocked")
            print("FocusVault hosts file: \(arguments.hostsFileURL.path)")
        case .allowlist:
            print("FocusVault YouTube channel vault defaults:")
            for channel in YouTubeChannelDefaults.channels {
                print("- \(channel.name) \(channel.displayHandle) [\(channel.channelID)]")
            }
            print("Use the BrowserExtension mode to allow these channels while blocking other YouTube pages.")
        }
    }

    private static func printUsage() {
        print(
            """
            FocusVault — a free macOS website blocker
            Vault in. Get work done.

            Short commands:
              block      Engage the focus vault for YouTube.
              unblock    Open the vault and remove its managed section.
              status     Show whether the vault is engaged.
              allowlist  Show the default YouTube channels allowed by channel-vault mode.
              version    Print the installed version.

            Usage:
              focusvault block [--domain DOMAIN ...] [--hosts-file PATH] [--dry-run]
              focusvault unblock [--hosts-file PATH]
              focusvault status [--hosts-file PATH]
              focusvault allowlist
              focusvault version

            By default FocusVault manages a marked section in /etc/hosts for YouTube.
            Editing /etc/hosts normally requires sudo:

              sudo focusvault block
              focusvault status
              sudo focusvault unblock

            --hosts-file is intended for safe testing or a separate hosts file.
            """
        )
    }
}
