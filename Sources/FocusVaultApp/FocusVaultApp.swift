import SwiftUI

@main
struct FocusVaultApp: App {
    @StateObject private var model = FocusVaultAppModel()
    @StateObject private var tracker = ProductivityTracker()

    var body: some Scene {
        WindowGroup {
            FocusVaultDashboard()
                .environmentObject(model)
                .environmentObject(tracker)
                .frame(minWidth: 820, minHeight: 610)
        }
        .defaultSize(width: 920, height: 680)
        .windowStyle(.hiddenTitleBar)
    }
}
