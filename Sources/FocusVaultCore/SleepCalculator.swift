import Foundation

public enum SleepCalculationDirection: String, CaseIterable, Codable, Equatable {
    case wakeTime
    case bedtime

    public var title: String {
        switch self {
        case .wakeTime:
            return "Wake time"
        case .bedtime:
            return "Bedtime"
        }
    }
}

public struct SleepRecommendation: Codable, Equatable {
    public let time: Date
    public let cycles: Int
    public let sleepMinutes: Int

    public init(time: Date, cycles: Int, sleepMinutes: Int) {
        self.time = time
        self.cycles = cycles
        self.sleepMinutes = sleepMinutes
    }

    public var sleepHours: Double {
        Double(sleepMinutes) / 60.0
    }
}

/// Sleep-cycle timing helper. It uses five or six 90-minute cycles by default
/// and accounts for an average 14-minute wind-down/fall-asleep period.
public enum SleepCalculator {
    public static let sleepCycleMinutes = 90
    public static let fallAsleepMinutes = 14
    public static let recommendedCycleCounts = [6, 5, 4]

    public static func recommendations(
        direction: SleepCalculationDirection,
        time: Date,
        calendar: Calendar = .current,
        cycleCounts: [Int] = recommendedCycleCounts
    ) -> [SleepRecommendation] {
        switch direction {
        case .wakeTime:
            return bedtimes(
                for: time,
                calendar: calendar,
                cycleCounts: cycleCounts
            )
        case .bedtime:
            return wakeTimes(
                for: time,
                calendar: calendar,
                cycleCounts: cycleCounts
            )
        }
    }

    public static func bedtimes(
        for wakeTime: Date,
        calendar: Calendar = .current,
        cycleCounts: [Int] = recommendedCycleCounts
    ) -> [SleepRecommendation] {
        validCycleCounts(cycleCounts).map { cycles in
            let minutes = totalMinutes(for: cycles)
            let bedtime = calendar.date(
                byAdding: .minute,
                value: -minutes,
                to: wakeTime
            ) ?? wakeTime.addingTimeInterval(-TimeInterval(minutes * 60))
            return SleepRecommendation(
                time: bedtime,
                cycles: cycles,
                sleepMinutes: cycles * sleepCycleMinutes
            )
        }
    }

    public static func wakeTimes(
        for bedtime: Date,
        calendar: Calendar = .current,
        cycleCounts: [Int] = recommendedCycleCounts
    ) -> [SleepRecommendation] {
        validCycleCounts(cycleCounts).map { cycles in
            let minutes = totalMinutes(for: cycles)
            let wakeTime = calendar.date(
                byAdding: .minute,
                value: minutes,
                to: bedtime
            ) ?? bedtime.addingTimeInterval(TimeInterval(minutes * 60))
            return SleepRecommendation(
                time: wakeTime,
                cycles: cycles,
                sleepMinutes: cycles * sleepCycleMinutes
            )
        }
    }

    private static func totalMinutes(for cycles: Int) -> Int {
        (cycles * sleepCycleMinutes) + fallAsleepMinutes
    }

    private static func validCycleCounts(_ values: [Int]) -> [Int] {
        var seen = Set<Int>()
        return values
            .filter { (1...12).contains($0) }
            .filter { seen.insert($0).inserted }
    }
}

public typealias VaultySleepCalculator = SleepCalculator
