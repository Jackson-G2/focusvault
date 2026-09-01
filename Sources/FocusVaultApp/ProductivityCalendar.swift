import SwiftUI
import FocusVaultCore

struct ProductivityCalendar: View {
    let log: ProductivityLog

    private let calendar: Calendar
    private let weekCount = 13

    init(log: ProductivityLog) {
        self.log = log
        self.calendar = Calendar.current
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 8) {
                            Text("Productivity")
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                            if #available(macOS 26.0, *) {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.green)
                                    .glassEffect(.regular.tint(.green.opacity(0.18)), in: .circle)
                            }
                        }
                        Text("Your personal active-work calendar, kept on this Mac.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(totalDescription)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.green)
                }

                HStack(alignment: .top, spacing: 8) {
                    weekdayLabels
                    weeks
                }

                HStack(spacing: 8) {
                    Text("Less")
                    ForEach(0..<5, id: \.self) { level in
                        ProductivityDot(level: level, size: 11)
                    }
                    Text("More")
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            }
            .padding(22)
        }
    }

    private var weekdayLabels: some View {
        VStack(alignment: .trailing, spacing: 5) {
            Text("")
                .frame(height: 11)
            ForEach(Array(["", "M", "", "W", "", "F", ""] .enumerated()), id: \.offset) { _, label in
                Text(label)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(width: 14, height: 11, alignment: .trailing)
            }
        }
    }

    private var weeks: some View {
        HStack(alignment: .top, spacing: 5) {
            ForEach(weekStarts, id: \.self) { weekStart in
                VStack(spacing: 5) {
                    Text(monthLabel(for: weekStart))
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .frame(height: 11)
                    ForEach(0..<7, id: \.self) { offset in
                        let date = calendar.date(byAdding: .day, value: offset, to: weekStart) ?? weekStart
                        ProductivityDot(level: intensity(for: date), size: 13)
                            .help(helpText(for: date))
                    }
                }
            }
        }
    }

    private var weekStarts: [Date] {
        guard let currentWeek = calendar.dateInterval(of: .weekOfYear, for: Date())?.start else {
            return []
        }
        return (0..<weekCount).compactMap { index in
            calendar.date(byAdding: .day, value: -7 * (weekCount - 1 - index), to: currentWeek)
        }
    }

    private var totalDescription: String {
        let total = log.totalMinutes(
            inLastDays: weekCount * 7,
            endingAt: Date(),
            calendar: calendar
        )
        if total < 60 {
            return "\(total)m logged"
        }
        return "\(total / 60)h \(total % 60)m logged"
    }

    private func intensity(for date: Date) -> Int {
        let minutes = log.minutes(on: date, calendar: calendar)
        switch minutes {
        case 0: return 0
        case 1...15: return 1
        case 16...60: return 2
        case 61...120: return 3
        default: return 4
        }
    }

    private func monthLabel(for date: Date) -> String {
        let month = calendar.component(.month, from: date)
        let year = calendar.component(.year, from: date)
        guard let firstWeek = weekStarts.first else { return "" }

        let shouldShow: Bool
        if date == firstWeek {
            shouldShow = true
        } else if let previousWeek = calendar.date(byAdding: .day, value: -7, to: date) {
            shouldShow = calendar.component(.month, from: previousWeek) != month ||
                calendar.component(.year, from: previousWeek) != year
        } else {
            shouldShow = false
        }

        return shouldShow ? calendar.shortMonthSymbols[month - 1] : ""
    }

    private func helpText(for date: Date) -> String {
        let minutes = log.minutes(on: date, calendar: calendar)
        let day = date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        return minutes == 0 ? "\(day): no productive time logged" : "\(day): \(minutes) productive minutes"
    }
}

private struct ProductivityDot: View {
    let level: Int
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .overlay {
                Circle().strokeBorder(.white.opacity(level == 0 ? 0.12 : 0.04), lineWidth: 1)
            }
    }

    private var color: Color {
        switch level {
        case 1: return .green.opacity(0.28)
        case 2: return .green.opacity(0.48)
        case 3: return .green.opacity(0.70)
        case 4: return .green
        default: return .white.opacity(0.10)
        }
    }
}
