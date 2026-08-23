import Darwin
import Foundation
import FrostwallCore

private enum CLIError: Error, LocalizedError {
    case missingValue(option: String)
    case unknownCommand(String)
    case unknownArgument(String)
    case invalidOption(command: String, option: String)

    var errorDescription: String? {
        switch self {
        case let .missingValue(option):
            return "Missing value for \(option)."
        case let .unknownCommand(command):
            return "Unknown command: \(command)."
        case let .unknownArgument(argument):
            return "Unknown argument: \(argument)."
        case let .invalidOption(command, option):
            return "\(option) cannot be used with \(command)."
        }
    }
}

private enum Command {
    case block
    case unblock
    case status
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
private struct FrostwallCLI {
    private static let version = "0.1.0"

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
            return Arguments(
                command: .help,
                hostsFileURL: HostBlocker.defaultHostsFileURL,
                domains: HostBlocker.defaultDomains,
                dryRun: false
            )
        }

        let command: Command
        switch commandName.lowercased() {
        case "block":
            command = .block
        case "unblock", "un-block":
            command = .unblock
        case "status":
            command = .status
        case "help", "--help", "-h":
            return Arguments(
                command: .help,
                hostsFileURL: HostBlocker.defaultHostsFileURL,
                domains: HostBlocker.defaultDomains,
                dryRun: false
            )
        case "version", "--version", "-v":
            return Arguments(
                command: .version,
                hostsFileURL: HostBlocker.defaultHostsFileURL,
                domains: HostBlocker.defaultDomains,
                dryRun: false
            )
        default:
            throw CLIError.unknownCommand(commandName)
        }

        var hostsFileURL = HostBlocker.defaultHostsFileURL
        var customDomains: [String] = []
        var sawCustomDomain = false
        var dryRun = false
        var index = 1

        while index < rawArguments.count {
            let argument = rawArguments[index]
            switch argument {
            case "--hosts-file":
                guard index + 1 < rawArguments.count else {
                    throw CLIError.missingValue(option: argument)
                }
                hostsFileURL = URL(fileURLWithPath: rawArguments[index + 1])
                index += 2
            case "--domain":
                guard index + 1 < rawArguments.count else {
                    throw CLIError.missingValue(option: argument)
                }
                customDomains.append(rawArguments[index + 1])
                sawCustomDomain = true
                index += 2
            case "--dry-run":
                dryRun = true
                index += 1
            case "--help", "-h":
                return Arguments(
                    command: .help,
                    hostsFileURL: HostBlocker.defaultHostsFileURL,
                    domains: HostBlocker.defaultDomains,
                    dryRun: false
                )
            default:
                throw CLIError.unknownArgument(argument)
            }
        }

        if dryRun && command != .block {
            throw CLIError.invalidOption(command: commandName, option: "--dry-run")
        }

        return Arguments(
            command: command,
            hostsFileURL: hostsFileURL,
            domains: sawCustomDomain ? customDomains : HostBlocker.defaultDomains,
            dryRun: dryRun
        )
    }

    private static func run(_ arguments: Arguments) throws {
        switch arguments.command {
        case .help:
            printUsage()
        case .version:
            print("frostwall \(version)")
        case .block:
            let blocker = try HostBlocker(
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
                print("Blocked \(blocker.domains.joined(separator: ", ")).")
            } else {
                print("Already blocked.")
            }
        case .unblock:
            let blocker = try HostBlocker(
                hostsFileURL: arguments.hostsFileURL,
                domains: HostBlocker.defaultDomains
            )
            let changed = try blocker.unblock()
            print(changed ? "Unblocked Frostwall's managed section." : "Already unblocked.")
        case .status:
            let blocker = try HostBlocker(
                hostsFileURL: arguments.hostsFileURL,
                domains: HostBlocker.defaultDomains
            )
            let blocked = try blocker.isBlocked()
            print(blocked ? "blocked" : "unblocked")
            print("hosts file: \(arguments.hostsFileURL.path)")
        }
    }

    private static func printUsage() {
        print(
            """
            Frostwall — a transparent macOS website blocker

            Usage:
              frostwall block [--domain DOMAIN ...] [--hosts-file PATH] [--dry-run]
              frostwall unblock [--hosts-file PATH]
              frostwall status [--hosts-file PATH]
              frostwall version

            By default Frostwall manages a marked section in /etc/hosts for YouTube.
            Editing /etc/hosts normally requires sudo:

              sudo frostwall block
              frostwall status
              sudo frostwall unblock

            --hosts-file is intended for testing or a separate hosts file.
            """
        )
    }
}
