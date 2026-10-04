import Darwin
import Foundation
import VaultyCore

struct SelfTestFailure: Error, CustomStringConvertible {
    let message: String

    var description: String { message }
}

struct Fixture {
    let directory: URL
    let hostsFile: URL
}

let defaultFixtureContents = "# existing entry\n127.0.0.1 localhost\n"

func testCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    calendar.locale = Locale(identifier: "en_US_POSIX")
    return calendar
}

func testDate(
    _ year: Int,
    _ month: Int,
    _ day: Int,
    _ hour: Int = 12,
    _ minute: Int = 0
) -> Date {
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    components.hour = hour
    components.minute = minute
    return testCalendar().date(from: components)!
}

func check(_ condition: Bool, _ message: String) throws {
    guard condition else {
        throw SelfTestFailure(message: message)
    }
}

func checkEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) throws {
    guard actual == expected else {
        throw SelfTestFailure(message: "\(message)\nexpected: \(expected)\nactual: \(actual)")
    }
}

func read(_ url: URL) throws -> String {
    try String(contentsOf: url, encoding: .utf8)
}

func write(_ contents: String, to url: URL) throws {
    try contents.write(to: url, atomically: true, encoding: .utf8)
}

func makeDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("focusvault-self-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
    )
    return directory
}

func makeFixture(initial: String = defaultFixtureContents) throws -> Fixture {
    let directory = try makeDirectory()
    let hostsFile = directory.appendingPathComponent("hosts")
    try write(initial, to: hostsFile)
    return Fixture(directory: directory, hostsFile: hostsFile)
}

func withFixture(
    initial: String = defaultFixtureContents,
    _ body: (URL) throws -> Void
) throws {
    let fixture = try makeFixture(initial: initial)
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    try body(fixture.hostsFile)
}

func withMissingHostsFile(_ body: (Fixture) throws -> Void) throws {
    let directory = try makeDirectory()
    let fixture = Fixture(
        directory: directory,
        hostsFile: directory.appendingPathComponent("missing-hosts")
    )
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    try body(fixture)
}

func expectFocusVaultError(
    _ work: () throws -> Void,
    _ message: String,
    matching predicate: ((FocusVaultError) -> Bool)? = nil
) throws {
    do {
        try work()
        throw SelfTestFailure(message: "expected VaultyError: \(message)")
    } catch let error as FocusVaultError {
        if let predicate, !predicate(error) {
            throw SelfTestFailure(message: "wrong VaultyError for \(message): \(error)")
        }
    }
}

func expectProductivityLogError(
    _ work: () throws -> Void,
    _ message: String,
    matching predicate: ((ProductivityLogError) -> Bool)? = nil
) throws {
    do {
        try work()
        throw SelfTestFailure(message: "expected ProductivityLogError: \(message)")
    } catch let error as ProductivityLogError {
        if let predicate, !predicate(error) {
            throw SelfTestFailure(message: "wrong ProductivityLogError for \(message): \(error)")
        }
    }
}

func expectInvalidDomain(_ value: String) throws {
    try expectFocusVaultError(
        { _ = try FocusVaultBlocker.normalizeDomain(value) },
        "invalid domain \(value)",
        matching: { error in
            if case .invalidDomain = error { return true }
            return false
        }
    )
}
