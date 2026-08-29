import SwiftUI

@main
struct FocusVaultApp: App {
    @StateObject private var model = FocusVaultAppModel()

    var body: some Scene {
        WindowGroup {
            FocusVaultDashboard()
                .environmentObject(model)
                .frame(minWidth: 820, minHeight: 610)
        }
        .defaultSize(width: 920, height: 680)
        .windowStyle(.hiddenTitleBar)
    }
}
