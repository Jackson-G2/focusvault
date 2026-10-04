import Foundation

/// Non-GUI entrypoints stay outside the SwiftUI application lifecycle. Missing
/// fixture/output arguments are errors, never a reason to launch the real GUI.
@MainActor
enum AppCommandDispatcher {
    static func execute(arguments: [String]) -> Int32? {
        let commands: [(String, (String) -> Int32)] = [
            ("--tool-supervisor", { LocalToolProcessSupervisor.run(configurationPath: $0) }),
            ("--render-tools-preview", VaultyVisualSnapshot.renderTools),
            ("--render-signal-shift-preview", VaultyVisualSnapshot.renderSignalShift),
            ("--render-signal-success-preview", VaultyVisualSnapshot.renderSignalShiftSuccess),
            ("--render-unlock-hub-preview", VaultyVisualSnapshot.renderUnlockHub),
            ("--render-grid-shot-preview", VaultyVisualSnapshot.renderGridShot),
            ("--render-grid-shot-success-preview", VaultyVisualSnapshot.renderGridShotSuccess),
            ("--render-typing-preview", VaultyVisualSnapshot.renderTypingSprint),
            ("--render-typing-success-preview", VaultyVisualSnapshot.renderTypingSprintSuccess),
            ("--render-dashboard-preview", VaultyVisualSnapshot.renderDashboard),
            ("--tools-live-smoke", { VaultyAppInteractionSelfTest.runLiveToolsSmoke(workspaceDirectory: $0) })
        ]
        for (flag, command) in commands where arguments.contains(flag) {
            guard let value = parameter(after: flag, in: arguments) else {
                fputs("usage: Vaulty \(flag) <path>\n", stderr)
                return 2
            }
            return command(value)
        }
        if arguments.contains("--self-test") { return VaultyAppInteractionSelfTest.run() }
        return nil
    }

    static func parameter(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count,
              !arguments[index + 1].isEmpty, !arguments[index + 1].hasPrefix("--") else { return nil }
        return arguments[index + 1]
    }
}
