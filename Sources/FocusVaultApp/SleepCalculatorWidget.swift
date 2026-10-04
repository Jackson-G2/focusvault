import SwiftUI
import VaultyCore

@MainActor
struct SleepCalculatorWidget: View {
    @Binding var showingSleepCalculator: Bool

    var body: some View {
        GlassCard(cornerRadius: 20, tint: Tideglass.seafoam) {
            HStack(spacing: 12) {
                GlassIcon(systemName: "bed.double.fill", tint: Tideglass.seafoam, size: 34)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Sleep calculator")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Tideglass.ink)
                    Text("Plan bedtime from sleep cycles")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Tideglass.muted)
                        .lineLimit(2)
                }

                Spacer(minLength: 4)

                Button {
                    showingSleepCalculator = true
                } label: {
                    Text("Open")
                }
                .buttonStyle(GlassButtonStyle(tint: Tideglass.seafoam, isProminent: true))
                .help("Open sleep calculator")
                .accessibilityLabel("Open sleep calculator")
                .accessibilityIdentifier("open-sleep-calculator")
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

}
