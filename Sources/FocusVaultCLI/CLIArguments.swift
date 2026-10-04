import Foundation
import VaultyCore

enum CLIError: Error, LocalizedError {
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

enum Command {
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

struct Arguments {
    let command: Command
    let hostsFileURL: URL
    let domains: [String]
    let dryRun: Bool
}

enum CLIArgumentParser {
    static func parse(_ rawArguments: [String]) throws -> Arguments {
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

}
