import Darwin
import SwiftUI

@main
struct VaultyApp: App {
    @StateObject private var model = FocusVaultAppModel()
    @StateObject private var tracker = ProductivityTracker()
    @StateObject private var learningGuide = VideoResearchModel()
    @StateObject private var toolsManager = LocalToolsManager()

    init() {
        if let status = AppCommandDispatcher.execute(arguments: CommandLine.arguments) {
            Darwin.exit(status)
        }
        Self.isGridShotGestureLab = CommandLine.arguments.contains("--grid-shot-gesture-lab")
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
