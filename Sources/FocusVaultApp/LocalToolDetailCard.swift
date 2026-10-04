import SwiftUI

struct LocalToolDetailCard: View {
    @EnvironmentObject private var manager: LocalToolsManager
    @ObservedObject var runtime: LocalToolRuntime
    @Binding var removalError: String?

    var body: some View {
        GlassCard(cornerRadius: 18, tint: runtime.isRunning ? Tideglass.seafoam : Tideglass.muted) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(runtime.definition.name)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(Tideglass.ink)
                        Text(runtime.definition.detail)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Tideglass.muted)
                    }
                    Spacer()
                    LocalToolLifecycleControls(runtime: runtime)
                    Button(role: .destructive) {
                        do {
                            try manager.remove(runtime)
                            removalError = nil
                        } catch {
                            removalError = error.localizedDescription
                        }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(GlassButtonStyle(tint: Tideglass.coral))
                    .help("Remove tool from Vaulty")
                }

                Text(runtime.errorText ?? runtime.statusText)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(runtime.errorText == nil ? Tideglass.muted : Tideglass.coral)
                ForEach(runtime.definition.links) { link in
                    HStack(spacing: 8) {
                        Text(link.name)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Tideglass.ink)
                            .frame(width: 92, alignment: .leading)
                        Text(link.urlString)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Tideglass.muted)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                        Spacer()
                        Button { manager.copy(link, for: runtime) } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(GlassButtonStyle(tint: Tideglass.muted))
                        Button { manager.open(link, for: runtime) } label: {
                            Image(systemName: "arrow.up.right.square")
                        }
                        .buttonStyle(GlassButtonStyle(tint: Tideglass.signal))
                    }
                }

                HStack {
                    Text("\(runtime.definition.executablePath) \(runtime.definition.arguments.joined(separator: " "))")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Tideglass.muted.opacity(0.8))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    if runtime.definition.updateMode != .none {
                        Button(runtime.isCheckingUpdate ? "Checking…" : "Check updates") {
                            manager.checkForUpdates(runtime)
                        }
                        .buttonStyle(GlassButtonStyle(tint: Tideglass.muted))
                        .disabled(runtime.isCheckingUpdate)
                    }
                }

                if let updateText = runtime.updateText {
                    Text(updateText)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Tideglass.muted)
                }
            }
            .padding(16)
        }
    }
}
