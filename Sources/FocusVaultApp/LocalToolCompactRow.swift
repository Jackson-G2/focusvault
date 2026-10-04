import SwiftUI

struct LocalToolCompactRow: View {
    @EnvironmentObject private var manager: LocalToolsManager
    @ObservedObject var runtime: LocalToolRuntime

    private var tint: Color {
        switch runtime.state {
        case .runningOwned: return Tideglass.seafoam
        case .runningExternal: return Tideglass.signal
        case .failed: return Tideglass.coral
        default: return Tideglass.muted
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                GlassIcon(systemName: runtime.definition.iconName, tint: tint, size: 32)

                VStack(alignment: .leading, spacing: 3) {
                    Text(runtime.definition.name)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Tideglass.ink)
                    Text(runtime.errorText ?? runtime.statusText)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(runtime.errorText == nil ? Tideglass.muted : Tideglass.coral)
                        .lineLimit(2)
                }

                Spacer(minLength: 3)

                Button {
                    manager.startOrOpen(runtime)
                } label: {
                    HStack(spacing: 5) {
                        if runtime.state == .checking || runtime.state == .starting {
                            ProgressView().controlSize(.small)
                        }
                        Text(runtime.actionTitle)
                    }
                }
                .buttonStyle(GlassButtonStyle(tint: tint, isProminent: true))
                .fixedSize()
                .disabled(runtime.state == .checking || runtime.state == .starting || runtime.state == .stopping)
                .accessibilityIdentifier("launch-tool-\(runtime.id.uuidString)")
            }

            LocalToolLifecycleControls(runtime: runtime)

            if let link = runtime.definition.links.first {
                HStack(spacing: 7) {
                    Text(link.urlString)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(Tideglass.muted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    Spacer(minLength: 3)
                    Button {
                        manager.copy(link, for: runtime)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Tideglass.signal)
                    .help("Copy local link")
                    .accessibilityLabel("Copy \(runtime.definition.name) link")
                    .accessibilityIdentifier("copy-tool-link-\(runtime.id.uuidString)")

                    if runtime.definition.updateMode != .none {
                        Button {
                            manager.checkForUpdates(runtime)
                        } label: {
                            if runtime.isCheckingUpdate {
                                ProgressView().controlSize(.mini)
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Tideglass.signal)
                        .help("Check for updates")
                        .accessibilityLabel("Check \(runtime.definition.name) for updates")
                    }
                }
            }

            if let updateText = runtime.updateText {
                Text(updateText)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Tideglass.muted)
                    .lineLimit(2)
            }
        }
    }
}
