import SwiftUI
import VaultyCore

struct DashboardErrorBanner: View {
    let error: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(Tideglass.coral)
            Text(error)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Tideglass.ink)
                .lineLimit(2)
            Spacer(minLength: 8)
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(GlassButtonStyle(tint: Tideglass.muted))
            .help("Dismiss error")
            .accessibilityLabel("Dismiss error")
            .accessibilityIdentifier("dismiss-error")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(Tideglass.coral.opacity(0.10))
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Tideglass.coral.opacity(0.25), lineWidth: 1)
                }
        }
    }

}
