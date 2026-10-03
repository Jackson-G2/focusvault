import SwiftUI

struct LocalToolLifecycleControls: View {
    @EnvironmentObject private var manager: LocalToolsManager
    @ObservedObject var runtime: LocalToolRuntime
    @State private var confirmingExternalBB = false
    @State private var externalRestart = false

    var body: some View {
        HStack(spacing: 6) {
            if runtime.canCancel {
                Button("Cancel") { manager.cancel(runtime) }
                    .buttonStyle(GlassButtonStyle(tint: Tideglass.coral))
                    .accessibilityIdentifier("cancel-tool-\(runtime.id.uuidString)")
            } else if runtime.canControlOwned {
                Button("Stop") { manager.stop(runtime) }
                    .buttonStyle(GlassButtonStyle(tint: Tideglass.coral))
                    .accessibilityIdentifier("stop-tool-\(runtime.id.uuidString)")
                Button("Restart") { manager.restart(runtime) }
                    .buttonStyle(GlassButtonStyle(tint: Tideglass.signal))
                    .help("Stop the owned service, verify exit and port closure, then start a fresh process")
                    .accessibilityIdentifier("restart-tool-\(runtime.id.uuidString)")
            } else if runtime.state == .runningExternal, BBExternalLifecycle.matches(runtime.definition) {
                Button("Stop") {
                    externalRestart = false
                    confirmingExternalBB = true
                }
                .buttonStyle(GlassButtonStyle(tint: Tideglass.coral))
                .accessibilityIdentifier("stop-external-bb-\(runtime.id.uuidString)")
                Button("Restart") {
                    externalRestart = true
                    confirmingExternalBB = true
                }
                .buttonStyle(GlassButtonStyle(tint: Tideglass.signal))
                .accessibilityIdentifier("restart-external-bb-\(runtime.id.uuidString)")
            }
            Button { manager.refreshStatus(runtime) } label: {
                Image(systemName: "arrow.clockwise")
            }
                .buttonStyle(GlassButtonStyle(tint: Tideglass.muted))
                .help("Refresh Status — does not restart the application")
                .accessibilityLabel("Refresh Status")
                .disabled(runtime.canCancel || runtime.state == .stopping)
                .accessibilityIdentifier("refresh-tool-status-\(runtime.id.uuidString)")
        }
        .fixedSize(horizontal: true, vertical: false)
        .alert(externalRestart ? "Restart bb?" : "Stop bb?", isPresented: $confirmingExternalBB) {
            Button("Cancel", role: .cancel) {}
            Button(externalRestart ? "Restart bb" : "Stop bb", role: .destructive) {
                if externalRestart { manager.restart(runtime) } else { manager.stop(runtime) }
            }
        } message: {
            Text("bb was started outside Vaulty. This interrupts running agent threads and terminals. Vaulty will use bb’s verified stop command; your saved conversations are not deleted.")
        }
    }
}
