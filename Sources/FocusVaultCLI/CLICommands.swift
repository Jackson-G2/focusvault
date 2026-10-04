import Foundation
import VaultyCore

enum CLICommands {
    static func run(_ arguments: Arguments, executableName: String) throws {
        switch arguments.command {
        case .help:
            CLIUsage.printUsage()
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

}
