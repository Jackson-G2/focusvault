import Darwin
import Foundation
import VaultyCore

enum CLIInternalCommands {
    static func run(_ arguments: [String]) throws -> Bool {
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
        case "internal-refactor-self-test":
            try CLIRefactorSelfTest.run()
        case "internal-verify-guard-config":
            try VaultyGuardConfiguration.verifyRenderedConfiguration()
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

}
