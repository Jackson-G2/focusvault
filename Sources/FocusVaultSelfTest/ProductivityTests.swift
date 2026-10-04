import Foundation
import VaultyCore

enum ProductivityTests {
    static let tests: [SelfTestCase] = [
        ("productivity log same-day aggregation", testProductivityLogAggregatesSameDay),
        ("productivity log day separation", testProductivityLogSeparatesDays),
        ("productivity log non-positive values", testProductivityLogIgnoresNonPositiveMinutes),
        ("productivity log overflow clamp", testProductivityLogClampsOverflow),
        ("productivity store persistence", testProductivityStorePersistsAndReloads),
        ("productivity store missing file", testProductivityStoreMissingFileStartsEmpty),
        ("productivity store legacy migration", testProductivityStoreMigratesLegacyFile),
        ("productivity store corrupt file", testProductivityStoreRejectsCorruptFile),
        ("productivity date key", testProductivityDateKeyUsesCalendarDay)
    ]
}

private func testProductivityLogAggregatesSameDay() throws {
    let calendar = testCalendar()
    let date = testDate(2026, 8, 23)
    var log = ProductivityLog()

    log.record(minutes: 15, at: date, calendar: calendar)
    log.record(minutes: 45, at: date.addingTimeInterval(3_600), calendar: calendar)

    try checkEqual(log.minutes(on: date, calendar: calendar), 60, "same-day minutes were not aggregated")
    try checkEqual(log.totalMinutes(inLastDays: 1, endingAt: date, calendar: calendar), 60, "same-day total is wrong")
}
private func testProductivityLogSeparatesDays() throws {
    let calendar = testCalendar()
    let first = testDate(2026, 8, 22)
    let second = testDate(2026, 8, 23)
    var log = ProductivityLog()

    log.record(minutes: 20, at: first, calendar: calendar)
    log.record(minutes: 35, at: second, calendar: calendar)

    try checkEqual(log.minutes(on: first, calendar: calendar), 20, "first day changed")
    try checkEqual(log.minutes(on: second, calendar: calendar), 35, "second day is wrong")
    try checkEqual(log.totalMinutes(inLastDays: 2, endingAt: second, calendar: calendar), 55, "two-day total is wrong")
}
private func testProductivityLogIgnoresNonPositiveMinutes() throws {
    let calendar = testCalendar()
    let date = testDate(2026, 8, 23)
    var log = ProductivityLog()

    log.record(minutes: 0, at: date, calendar: calendar)
    log.record(minutes: -10, at: date, calendar: calendar)

    try checkEqual(log.minutes(on: date, calendar: calendar), 0, "non-positive minutes were recorded")
    try checkEqual(log.totalMinutes(inLastDays: 0, endingAt: date, calendar: calendar), 0, "zero-day total is not zero")
}
private func testProductivityLogClampsOverflow() throws {
    let calendar = testCalendar()
    let date = testDate(2026, 8, 23)
    let key = ProductivityLog.dateKey(for: date, calendar: calendar)
    var log = ProductivityLog(minutesByDay: [key: Int.max])

    log.record(minutes: 1, at: date, calendar: calendar)
    try checkEqual(log.minutes(on: date, calendar: calendar), Int.max, "overflow was not clamped")
}
private func testProductivityStorePersistsAndReloads() throws {
    let calendar = testCalendar()
    let date = testDate(2026, 8, 23)
    let directory = try makeDirectory()
    let fileURL = directory.appendingPathComponent("nested/productivity.json")
    defer { try? FileManager.default.removeItem(at: directory) }

    let store = try ProductivityLogStore(fileURL: fileURL)
    try store.record(minutes: 90, at: date, calendar: calendar)
    let reloaded = try ProductivityLogStore(fileURL: fileURL)

    try checkEqual(reloaded.log.minutes(on: date, calendar: calendar), 90, "persisted productivity was not reloaded")
    try check(FileManager.default.fileExists(atPath: fileURL.path), "productivity file was not created")
}
private func testProductivityStoreMissingFileStartsEmpty() throws {
    let directory = try makeDirectory()
    let fileURL = directory.appendingPathComponent("productivity.json")
    defer { try? FileManager.default.removeItem(at: directory) }

    let store = try ProductivityLogStore(fileURL: fileURL)
    try check(store.log.minutesByDay.isEmpty, "missing productivity file did not start empty")
    try check(!FileManager.default.fileExists(atPath: fileURL.path), "initializing created an unnecessary file")
}
private func testProductivityStoreMigratesLegacyFile() throws {
    let calendar = testCalendar()
    let date = testDate(2026, 8, 23)
    let directory = try makeDirectory()
    let legacyURL = directory.appendingPathComponent("FocusVault/productivity.json")
    let newURL = directory.appendingPathComponent("Vaulty/productivity.json")
    defer { try? FileManager.default.removeItem(at: directory) }

    var legacyLog = ProductivityLog()
    legacyLog.record(minutes: 25, at: date, calendar: calendar)
    try FileManager.default.createDirectory(at: legacyURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try JSONEncoder().encode(legacyLog).write(to: legacyURL)

    let migrated = try ProductivityLogStore(fileURL: newURL, legacyFileURL: legacyURL)
    try checkEqual(migrated.log.minutes(on: date, calendar: calendar), 25, "legacy productivity data was not migrated")
    try check(FileManager.default.fileExists(atPath: newURL.path), "migrated Vaulty productivity file was not created")
    try check(FileManager.default.fileExists(atPath: legacyURL.path), "legacy productivity file was removed")
}
private func testProductivityStoreRejectsCorruptFile() throws {
    let directory = try makeDirectory()
    let fileURL = directory.appendingPathComponent("productivity.json")
    defer { try? FileManager.default.removeItem(at: directory) }
    try "not-json".write(to: fileURL, atomically: true, encoding: .utf8)

    try expectProductivityLogError({ _ = try ProductivityLogStore(fileURL: fileURL) }, "corrupt productivity file") { error in
        if case .unableToDecode = error { return true }
        return false
    }
}
private func testProductivityDateKeyUsesCalendarDay() throws {
    var calendar = testCalendar()
    calendar.timeZone = TimeZone(secondsFromGMT: 10 * 60 * 60)!
    let date = testCalendar().date(from: DateComponents(year: 2026, month: 8, day: 22, hour: 16))!

    try checkEqual(
        ProductivityLog.dateKey(for: date, calendar: calendar),
        "2026-08-23",
        "date key did not use the supplied calendar"
    )
}
