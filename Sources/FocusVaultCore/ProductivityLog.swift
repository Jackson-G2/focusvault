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

public final class ProductivityLogStore {
    public let fileURL: URL
    public private(set) var log: ProductivityLog

    public init(
        fileURL: URL = ProductivityLogStore.defaultFileURL(),
        initialLog: ProductivityLog = ProductivityLog()
    ) throws {
        self.fileURL = fileURL
        self.log = initialLog
        try reload()
    }

    public static func defaultFileURL() -> URL {
        let fileManager = FileManager.default
        let baseURL = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        return baseURL
            .appendingPathComponent("FocusVault", isDirectory: true)
            .appendingPathComponent("productivity.json")
    }

    public func reload() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return
        }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw ProductivityLogError.unableToRead(
                path: fileURL.path,
                reason: error.localizedDescription
            )
        }

        do {
            log = try JSONDecoder().decode(ProductivityLog.self, from: data)
        } catch {
            throw ProductivityLogError.unableToDecode(
                path: fileURL.path,
                reason: error.localizedDescription
            )
        }
    }

    public func record(
        minutes: Int,
        at date: Date = Date(),
        calendar: Calendar = .current
    ) throws {
        guard minutes > 0 else { return }
        var updated = log
        updated.record(minutes: minutes, at: date, calendar: calendar)
        try save(updated)
        log = updated
    }

    private func save(_ value: ProductivityLog) throws {
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(value)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw ProductivityLogError.unableToWrite(
                path: fileURL.path,
                reason: error.localizedDescription
            )
        }
    }
}
