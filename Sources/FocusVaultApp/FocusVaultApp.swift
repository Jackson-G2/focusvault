import SwiftUI

@main
struct FocusVaultApp: App {
    @StateObject private var model = FocusVaultAppModel()
    @StateObject private var tracker = ProductivityTracker()
    @StateObject private var learningGuide = VideoResearchModel()

    var body: some Scene {
        WindowGroup {
            FocusVaultDashboard()
                .environmentObject(model)
                .environmentObject(tracker)
                .environmentObject(learningGuide)
                .frame(minWidth: 820, minHeight: 610)
        }
        .defaultSize(width: 920, height: 680)
        .windowStyle(.hiddenTitleBar)
    }
}
