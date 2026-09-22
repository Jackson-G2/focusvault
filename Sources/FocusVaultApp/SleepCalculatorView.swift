import SwiftUI
import VaultyCore

struct SleepCalculatorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var direction: SleepCalculationDirection = .wakeTime
    @State private var selectedTime = Self.defaultWakeTime()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 22)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    controls
                    recommendationsCard
                    note
                }
                .padding(.bottom, 8)
            }
        }
        .padding(28)
        .frame(minWidth: 560, minHeight: 560)
        .background(Tideglass.canvas)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Sleep calculator")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(Tideglass.ink)
                Text("Build a calmer bedtime around your next wake-up.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Tideglass.muted)
            }
            Spacer()
            Button("Close") {
                dismiss()
            }
            .buttonStyle(GlassButtonStyle(tint: Tideglass.muted))
            .accessibilityIdentifier("sleep-calculator-close")
        }
    }

    private var controls: some View {
        GlassCard(cornerRadius: 22, tint: Tideglass.signal) {
            VStack(alignment: .leading, spacing: 16) {
                Text("CALCULATE FROM")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.6)
                    .foregroundStyle(Tideglass.signal)

                Picker("Calculate from", selection: $direction) {
                    ForEach(SleepCalculationDirection.allCases, id: \.self) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("sleep-calculator-direction")

                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: direction == .wakeTime ? "sunrise.fill" : "moon.stars.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Tideglass.signal)
                        .frame(width: 28)

                    DatePicker(
                        direction == .wakeTime ? "I want to wake at" : "I want to sleep at",
                        selection: $selectedTime,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .datePickerStyle(.field)
                    .labelsHidden()
                    .accessibilityLabel(direction == .wakeTime ? "Wake time" : "Bedtime")

                    Button {
                        selectedTime = Date()
                    } label: {
                        Label("Now", systemImage: "clock")
                    }
                    .buttonStyle(GlassButtonStyle(tint: Tideglass.muted))
                    .help("Use the current time")
                    .accessibilityIdentifier("sleep-calculator-now")
                }
            }
            .padding(20)
        }
    }

    private var recommendationsCard: some View {
        GlassCard(cornerRadius: 22, tint: Tideglass.seafoam) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text(direction == .wakeTime ? "Recommended bedtimes" : "Recommended wake times")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(Tideglass.ink)
                    Spacer()
                    Text("90 min cycles")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(Tideglass.seafoam)
                }

                ForEach(Array(recommendations.enumerated()), id: \.offset) { index, recommendation in
                    recommendationRow(recommendation, isPreferred: index == 1)
                }
            }
            .padding(20)
        }
    }

    private func recommendationRow(
        _ recommendation: SleepRecommendation,
        isPreferred: Bool
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: isPreferred ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isPreferred ? Tideglass.seafoam : Tideglass.muted)
                .font(.system(size: 18, weight: .semibold))

            VStack(alignment: .leading, spacing: 3) {
                Text(recommendation.time.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Tideglass.ink)
                Text("\(recommendation.cycles) cycles · \(sleepDuration(recommendation.sleepMinutes)) asleep")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Tideglass.muted)
            }

            Spacer()

            if isPreferred {
                Text("balanced")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(Tideglass.seafoam)
            }
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(recommendation.time.formatted(date: .abbreviated, time: .shortened)), " +
            "\(recommendation.cycles) sleep cycles"
        )
    }

    private var note: some View {
        Text("Planning guide only: it assumes about 14 minutes to fall asleep and 90-minute cycles. Your sleep needs can vary.")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Tideglass.muted)
            .fixedSize(horizontal: false, vertical: true)
            .opacity(reduceMotion ? 1 : 0.92)
    }

    private var recommendations: [SleepRecommendation] {
        SleepCalculator.recommendations(
            direction: direction,
            time: selectedTime,
            calendar: Calendar.current
        )
    }

    private func sleepDuration(_ minutes: Int) -> String {
        let hours = minutes / 60
        let remainder = minutes % 60
        if remainder == 0 {
            return "\(hours)h"
        }
        return "\(hours)h \(remainder)m"
    }

    private static func defaultWakeTime() -> Date {
        let calendar = Calendar.current
        let now = Date()
        let todayAtSeven = calendar.date(
            bySettingHour: 7,
            minute: 0,
            second: 0,
            of: now
        ) ?? now
        if todayAtSeven > now {
            return todayAtSeven
        }
        return calendar.date(byAdding: .day, value: 1, to: todayAtSeven) ?? now
    }
}
