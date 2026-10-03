import SwiftUI
import VaultyCore

@MainActor
struct ShortFormProtectionWidget: View {
    @EnvironmentObject private var model: FocusVaultAppModel

    var body: some View {
        GlassCard(cornerRadius: 24, tint: model.isShortFormBlocked ? Tideglass.seafoam : Tideglass.signal) {
            VStack(alignment: .leading, spacing: 17) {
                HStack {
                    Text("SHORT-FORM PROTECTION")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(1.6)
                        .foregroundStyle(Tideglass.muted)
                    Spacer()
                    GlassPill(
                        title: model.isShortFormBlocked ? "On" : "Off",
                        systemImage: model.isShortFormBlocked ? "checkmark" : "minus",
                        tint: model.isShortFormBlocked ? Tideglass.seafoam : Tideglass.muted
                    )
                }

                HStack(spacing: 12) {
                    GlassIcon(
                        systemName: model.isShortFormBlocked ? "hourglass" : "hourglass.bottomhalf.filled",
                        tint: model.isShortFormBlocked ? Tideglass.seafoam : Tideglass.signal,
                        size: 38
                    )
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Short-form blocker")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(Tideglass.ink)
                        Text(model.isShortFormBlocked
                            ? "TikTok, Reels, and Shorts are closed"
                            : "TikTok, Reels, and Shorts are open")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Tideglass.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                    Button {
                        model.toggleShortFormVault()
                    } label: {
                        VaultLockGlyph(state: model.isShortFormBlocked ? .locked : .open, size: 15)
                    }
                    .buttonStyle(GlassButtonStyle(tint: model.isShortFormBlocked ? Tideglass.seafoam : Tideglass.signal, isProminent: true))
                    .disabled(model.isBusy || model.youtubeUnlockRemainingSeconds > 0)
                    .help(model.youtubeUnlockRemainingSeconds > 0
                        ? "Lock YouTube before changing system-wide short-form protection"
                        : (model.isShortFormBlocked ? "Open short-form blocker" : "Engage short-form blocker"))
                    .accessibilityLabel(model.isShortFormBlocked ? "Open short-form blocker" : "Engage short-form blocker")
                    .accessibilityIdentifier("toggle-short-form-vault")
                }

                Text("TikTok · Instagram Reels · YouTube Shorts · Facebook Reels")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Tideglass.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

}
