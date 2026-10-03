import SwiftUI
import VaultyCore

@MainActor
struct YouTubeProtectionWidget: View {
    @EnvironmentObject private var model: FocusVaultAppModel

    var body: some View {
        GlassCard(cornerRadius: 24, tint: model.isSystemBlocked ? Tideglass.seafoam : Tideglass.signal) {
            VStack(alignment: .leading, spacing: 17) {
                HStack {
                    Text("YOUTUBE PROTECTION")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(1.6)
                        .foregroundStyle(Tideglass.muted)
                    Spacer()
                    GlassPill(
                        title: model.isSystemBlocked ? "Locked" : model.youtubeUnlockTimeText,
                        lockState: model.isSystemBlocked ? .locked : .open,
                        tint: model.isSystemBlocked ? Tideglass.seafoam : Tideglass.signal
                    )
                }

                HStack(spacing: 12) {
                    GlassIcon(
                        lockState: model.isSystemBlocked ? .locked : .open,
                        tint: model.isSystemBlocked ? Tideglass.seafoam : Tideglass.signal,
                        size: 38
                    )
                    VStack(alignment: .leading, spacing: 4) {
                        Text("YouTube blocker")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(Tideglass.ink)
                        Text(model.isSystemBlocked
                            ? "Task + administrator approval"
                            : "Open now · auto-locks at 45 minutes")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Tideglass.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                    Button {
                        model.toggleFullVault()
                    } label: {
                        HStack(spacing: 6) {
                            VaultLockGlyph(state: model.isSystemBlocked ? .locked : .open, size: 14)
                            Text(model.isSystemBlocked ? "Unlock" : "Lock now")
                        }
                    }
                    .buttonStyle(GlassButtonStyle(tint: model.isSystemBlocked ? Tideglass.seafoam : Tideglass.signal, isProminent: true))
                    .disabled(model.isBusy)
                    .help(model.isSystemBlocked ? "Choose a task, win, then approve the 45-minute unlock" : "Lock YouTube without a password")
                    .accessibilityLabel(model.isSystemBlocked ? "Unlock YouTube for 45 minutes" : "Lock YouTube now without a password")
                    .accessibilityIdentifier("toggle-youtube-vault")
                }

                Text(model.isGuardInstalled
                    ? "Lock anytime with no password. Every unlock lasts 45 minutes."
                    : "One administrator approval installs the guard; after that, only unlocking asks for a password.")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Tideglass.muted)
                    .fixedSize(horizontal: false, vertical: true)

                Divider().overlay(Tideglass.line)

                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Channel vault")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(Tideglass.ink)
                        Text("Keep trusted YouTube channels only")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Tideglass.muted)
                    }
                    Spacer()
                    Button {
                        model.revealBrowserCompanion()
                    } label: {
                        Image(systemName: "arrow.up.right.square")
                    }
                    .buttonStyle(GlassButtonStyle(tint: Tideglass.muted))
                    .help("Open channel-vault setup")
                    .accessibilityLabel("Open channel-vault setup")
                    .accessibilityIdentifier("open-channel-vault-setup")
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

}
