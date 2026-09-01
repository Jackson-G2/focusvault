import SwiftUI
import FocusVaultCore

private enum VaultMode: String, CaseIterable {
    case channels
    case everything

    var title: String {
        switch self {
        case .channels: return "Channel Vault"
        case .everything: return "Full Vault"
        }
    }

    var subtitle: String {
        switch self {
        case .channels: return "Allow trusted channels only"
        case .everything: return "Block all of YouTube"
        }
    }
}

struct FocusVaultDashboard: View {
    @EnvironmentObject private var model: FocusVaultAppModel
    @EnvironmentObject private var tracker: ProductivityTracker
    @State private var selectedMode: VaultMode = .channels

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    statusCard
                    ProductivityCalendar(log: tracker.log)
                    modePicker
                    selectedModeContent
                    footer
                }
                .padding(30)
                .frame(maxWidth: 980)
                .frame(maxWidth: .infinity)
            }
        }
        .preferredColorScheme(.dark)
        .task {
            model.refresh()
            tracker.start()
        }
    }

    private var header: some View {
        GlassCard {
            HStack(spacing: 16) {
                GlassIcon(systemName: "lock.shield.fill", tint: .yellow)
                VStack(alignment: .leading, spacing: 5) {
                    Text("FocusVault")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text("Vault in. Get work done.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                GlassPill(
                    title: model.isSystemBlocked ? "Full vault engaged" : "Ready to focus",
                    systemImage: model.isSystemBlocked ? "lock.fill" : "sparkles",
                    tint: model.isSystemBlocked ? .orange : .green
                )
            }
            .padding(24)
        }
    }

    private var statusCard: some View {
        GlassCard(cornerRadius: 20) {
            HStack(spacing: 14) {
                Image(systemName: model.isSystemBlocked ? "lock.circle.fill" : "checkmark.circle.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(model.isSystemBlocked ? .orange : .green)
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.statusMessage)
                        .font(.system(size: 14, weight: .semibold))
                    Text(model.isSystemBlocked
                         ? "Your Mac is blocking the YouTube domains."
                         : "Choose a vault below to protect your attention.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if model.isBusy {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(18)
        }
    }

    private var modePicker: some View {
        GlassGroup {
            HStack(alignment: .top, spacing: 16) {
                modeCard(.channels, icon: "person.2.fill", tint: .cyan)
                modeCard(.everything, icon: "lock.fill", tint: .orange)
            }
        }
    }

    private func modeCard(_ mode: VaultMode, icon: String, tint: Color) -> some View {
        Button {
            selectedMode = mode
        } label: {
            GlassCard(cornerRadius: 24) {
                VStack(alignment: .leading, spacing: 13) {
                    HStack {
                        GlassIcon(systemName: icon, tint: tint)
                        Spacer()
                        Image(systemName: selectedMode == mode ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selectedMode == mode ? tint : .secondary)
                    }
                    Text(mode.title)
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                    Text(mode.subtitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .overlay {
                if selectedMode == mode {
                    RoundedRectangle(cornerRadius: 24)
                        .strokeBorder(tint.opacity(0.7), lineWidth: 1.5)
                }
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var selectedModeContent: some View {
        switch selectedMode {
        case .channels:
            channelVaultCard
        case .everything:
            fullVaultCard
        }
    }

    private var channelVaultCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Your allowed channels")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                        Text("Only these channels can open in the browser companion.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    GlassPill(title: "2 allowed", systemImage: "checkmark.seal.fill", tint: .cyan)
                }

                VStack(spacing: 10) {
                    ForEach(model.defaultChannels, id: \.channelID) { channel in
                        channelRow(channel)
                    }
                }

                Divider().overlay(.white.opacity(0.12))

                HStack(alignment: .center, spacing: 14) {
                    Image(systemName: "puzzlepiece.extension.fill")
                        .foregroundStyle(.cyan)
                    Text("The app includes the browser companion. Load it once from the folder below to activate channel filtering in Chrome, Edge, or Brave.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Show companion") {
                        model.revealBrowserCompanion()
                    }
                    .buttonStyle(GlassButtonStyle(tint: .cyan))
                }
            }
            .padding(24)
        }
    }

    private func channelRow(_ channel: AllowedYouTubeChannel) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 3) {
                Text(channel.name)
                    .font(.system(size: 14, weight: .semibold))
                Text(channel.displayHandle)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("Allowed")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.green)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background {
#if swift(>=6.0)
            if #available(macOS 26.0, *) {
                Color.clear.glassEffect(.regular, in: .rect(cornerRadius: 15))
            } else {
                fallbackChannelBackground
            }
#else
            fallbackChannelBackground
#endif
        }
    }

    private var fallbackChannelBackground: some View {
        RoundedRectangle(cornerRadius: 15)
            .fill(.white.opacity(0.07))
    }

    private var fullVaultCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Block all YouTube")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                        Text("The strongest mode. No YouTube domains will load on this Mac.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    GlassPill(title: "Mac-wide", systemImage: "desktopcomputer", tint: .orange)
                }

                HStack {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.orange)
                    Text("FocusVault will ask macOS for administrator permission before changing the hosts file.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                Button {
                    model.toggleFullVault()
                } label: {
                    Label(
                        model.isSystemBlocked ? "Open full vault" : "Engage full vault",
                        systemImage: model.isSystemBlocked ? "lock.open.fill" : "lock.fill"
                    )
                }
                .buttonStyle(GlassButtonStyle(tint: .orange, isProminent: true))
                .disabled(model.isBusy)
            }
            .padding(24)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let error = model.lastError {
                GlassCard(cornerRadius: 16) {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text(error)
                            .font(.system(size: 12))
                        Spacer()
                        Button("Dismiss") {
                            model.clearError()
                        }
                        .buttonStyle(GlassButtonStyle(tint: .red))
                    }
                    .padding(14)
                }
            }

            HStack {
                Text("FocusVault 0.5.0")
                Text("•")
                Text("Free and open source")
                Spacer()
                Text("Liquid Glass interface for macOS 26+")
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
        }
    }
}
