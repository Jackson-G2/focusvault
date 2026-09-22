import Darwin
import SwiftUI

@main
struct VaultyApp: App {
    @StateObject private var model = FocusVaultAppModel()
    @StateObject private var tracker = ProductivityTracker()
    @StateObject private var learningGuide = VideoResearchModel()
    @StateObject private var toolsManager = LocalToolsManager()

    init() {
        if let index = CommandLine.arguments.firstIndex(of: "--tool-supervisor"),
           index + 1 < CommandLine.arguments.count {
            Darwin.exit(
                LocalToolProcessSupervisor.run(
                    configurationPath: CommandLine.arguments[index + 1]
                )
            )
        }
        if let index = CommandLine.arguments.firstIndex(of: "--render-tools-preview"),
           index + 1 < CommandLine.arguments.count {
            Darwin.exit(VaultyVisualSnapshot.renderTools(to: CommandLine.arguments[index + 1]))
        }
        if let index = CommandLine.arguments.firstIndex(of: "--render-signal-shift-preview"),
           index + 1 < CommandLine.arguments.count {
            Darwin.exit(VaultyVisualSnapshot.renderSignalShift(to: CommandLine.arguments[index + 1]))
        }
        if let index = CommandLine.arguments.firstIndex(of: "--render-signal-success-preview"),
           index + 1 < CommandLine.arguments.count {
            Darwin.exit(VaultyVisualSnapshot.renderSignalShiftSuccess(to: CommandLine.arguments[index + 1]))
        }
        if let index = CommandLine.arguments.firstIndex(of: "--render-unlock-hub-preview"),
           index + 1 < CommandLine.arguments.count {
            Darwin.exit(VaultyVisualSnapshot.renderUnlockHub(to: CommandLine.arguments[index + 1]))
        }
        if let index = CommandLine.arguments.firstIndex(of: "--render-grid-shot-preview"),
           index + 1 < CommandLine.arguments.count {
            Darwin.exit(VaultyVisualSnapshot.renderGridShot(to: CommandLine.arguments[index + 1]))
        }
        if let index = CommandLine.arguments.firstIndex(of: "--render-grid-shot-success-preview"),
           index + 1 < CommandLine.arguments.count {
            Darwin.exit(VaultyVisualSnapshot.renderGridShotSuccess(to: CommandLine.arguments[index + 1]))
        }
        if let index = CommandLine.arguments.firstIndex(of: "--render-typing-preview"),
           index + 1 < CommandLine.arguments.count {
            Darwin.exit(VaultyVisualSnapshot.renderTypingSprint(to: CommandLine.arguments[index + 1]))
        }
        if let index = CommandLine.arguments.firstIndex(of: "--render-typing-success-preview"),
           index + 1 < CommandLine.arguments.count {
            Darwin.exit(VaultyVisualSnapshot.renderTypingSprintSuccess(to: CommandLine.arguments[index + 1]))
        }
        if let index = CommandLine.arguments.firstIndex(of: "--render-dashboard-preview"),
           index + 1 < CommandLine.arguments.count {
            Darwin.exit(VaultyVisualSnapshot.renderDashboard(to: CommandLine.arguments[index + 1]))
        }
        if CommandLine.arguments.contains("--grid-shot-gesture-lab") {
            Self.isGridShotGestureLab = true
            return
        }
        if CommandLine.arguments.contains("--tools-live-smoke") {
            guard let index = CommandLine.arguments.firstIndex(of: "--tools-live-smoke"),
                  index + 1 < CommandLine.arguments.count else {
                fputs("usage: Vaulty --tools-live-smoke <workspace-directory>\n", stderr)
                Darwin.exit(2)
            }
            Darwin.exit(VaultyAppInteractionSelfTest.runLiveToolsSmoke(
                workspaceDirectory: CommandLine.arguments[index + 1]
            ))
        }
        if CommandLine.arguments.contains("--self-test") {
            Darwin.exit(VaultyAppInteractionSelfTest.run())
        }
    }

    private static var isGridShotGestureLab = false

    var body: some Scene {
        WindowGroup {
            if Self.isGridShotGestureLab {
                GridShotChallengeView(
                    onComplete: {},
                    onFailure: {},
                    onCancel: {},
                    onChooseAnother: {},
                    isUnlocking: false,
                    unlockError: nil,
                    initialPhase: .running
                )
                .frame(width: UnlockChallengeLayout.width, height: UnlockChallengeLayout.height)
            } else {
                FocusVaultDashboard()
                .environmentObject(model)
                .environmentObject(tracker)
                .environmentObject(learningGuide)
                .environmentObject(toolsManager)
                .frame(minWidth: 820, minHeight: 610)
                .onOpenURL { url in
                    model.handleOpenURL(url)
                }
            }
        }
        .defaultSize(width: 920, height: 680)
        .windowStyle(.hiddenTitleBar)
    }
}
