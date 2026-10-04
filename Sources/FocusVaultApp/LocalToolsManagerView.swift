import SwiftUI

struct LocalToolsManagerView: View {
    @EnvironmentObject private var manager: LocalToolsManager
    @Environment(\.dismiss) private var dismiss
    @State private var removalError: String?

    var body: some View {
        ZStack {
            AppBackground()
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Local tools")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundStyle(Tideglass.ink)
                        Text("Vaulty stops only process groups it started. Reused services stay untouched.")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Tideglass.muted)
                    }
                    Spacer()
                    Button("Done") { dismiss() }
                        .buttonStyle(GlassButtonStyle(tint: Tideglass.signal, isProminent: true))
                }

                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(manager.tools) { runtime in
                            LocalToolDetailCard(runtime: runtime, removalError: $removalError)
                        }
                    }
                }

                if let removalError {
                    Text(removalError)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Tideglass.coral)
                }

                Button {
                    manager.isPresentingManager = false
                    DispatchQueue.main.async { manager.isPresentingAddTool = true }
                } label: {
                    Label("Add tool", systemImage: "plus")
                }
                .buttonStyle(GlassButtonStyle(tint: Tideglass.signal, isProminent: true))
            }
            .padding(28)
        }
        .preferredColorScheme(.dark)
        .frame(minWidth: 640, minHeight: 560)
    }
}
