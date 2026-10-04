import Foundation

public enum ProductivityLogError: Error, LocalizedError, Equatable {
    case unableToRead(path: String, reason: String)
    case unableToDecode(path: String, reason: String)
    case unableToWrite(path: String, reason: String)

    public var errorDescription: String? {
        switch self {
        case let .unableToRead(path, reason):
            return "Could not read productivity log \(path): \(reason)"
        case let .unableToDecode(path, reason):
            return "Could not decode productivity log \(path): \(reason)"
        case let .unableToWrite(path, reason):
            return "Could not write productivity log \(path): \(reason)"
        }
    }
}

public struct ProductivityLog: Codable, Equatable {
    public private(set) var minutesByDay: [String: Int]

    public init(minutesByDay: [String: Int] = [:]) {
        self.minutesByDay = minutesByDay.filter { $0.value >= 0 }
    }

    public mutating func record(
        minutes: Int,
        at date: Date = Date(),
        calendar: Calendar = .current
    ) {
        guard minutes > 0 else { return }
        let key = Self.dateKey(for: date, calendar: calendar)
        let current = minutesByDay[key, default: 0]
        let (updated, overflow) = current.addingReportingOverflow(minutes)
        minutesByDay[key] = overflow ? Int.max : updated
    }

    public func minutes(
        on date: Date = Date(),
        calendar: Calendar = .current
    ) -> Int {
        minutesByDay[Self.dateKey(for: date, calendar: calendar), default: 0]
    }

    public func totalMinutes(
        inLastDays count: Int,
        endingAt date: Date = Date(),
        calendar: Calendar = .current
    ) -> Int {
        guard count > 0 else { return 0 }
        let start = calendar.date(byAdding: .day, value: -(count - 1), to: date) ?? date
        return (0..<count).reduce(into: 0) { total, offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { return }
            let minutes = self.minutes(on: day, calendar: calendar)
            let (updated, overflow) = total.addingReportingOverflow(minutes)
            total = overflow ? Int.max : updated
        }
    }

    public static func dateKey(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04ld-%02ld-%02ld",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }
}
