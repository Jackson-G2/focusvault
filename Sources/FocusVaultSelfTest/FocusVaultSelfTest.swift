import Darwin
import Foundation
import VaultyCore

private struct SelfTestFailure: Error, CustomStringConvertible {
    let message: String

    var description: String { message }
}

private struct Fixture {
    let directory: URL
    let hostsFile: URL
}

private let defaultFixtureContents = "# existing entry\n127.0.0.1 localhost\n"

private func testCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    calendar.locale = Locale(identifier: "en_US_POSIX")
    return calendar
}

private func testDate(
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

private func check(_ condition: Bool, _ message: String) throws {
    guard condition else {
        throw SelfTestFailure(message: message)
    }
}

private func checkEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) throws {
    guard actual == expected else {
        throw SelfTestFailure(message: "\(message)\nexpected: \(expected)\nactual: \(actual)")
    }
}

private func read(_ url: URL) throws -> String {
    try String(contentsOf: url, encoding: .utf8)
}

private func write(_ contents: String, to url: URL) throws {
    try contents.write(to: url, atomically: true, encoding: .utf8)
}

private func makeDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("focusvault-self-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
    )
    return directory
}

private func makeFixture(initial: String = defaultFixtureContents) throws -> Fixture {
    let directory = try makeDirectory()
    let hostsFile = directory.appendingPathComponent("hosts")
    try write(initial, to: hostsFile)
    return Fixture(directory: directory, hostsFile: hostsFile)
}

private func withFixture(
    initial: String = defaultFixtureContents,
    _ body: (URL) throws -> Void
) throws {
    let fixture = try makeFixture(initial: initial)
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    try body(fixture.hostsFile)
}

private func withMissingHostsFile(_ body: (Fixture) throws -> Void) throws {
    let directory = try makeDirectory()
    let fixture = Fixture(
        directory: directory,
        hostsFile: directory.appendingPathComponent("missing-hosts")
    )
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    try body(fixture)
}

private func expectFocusVaultError(
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

private func expectProductivityLogError(
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

private func expectInvalidDomain(_ value: String) throws {
    try expectFocusVaultError(
        { _ = try FocusVaultBlocker.normalizeDomain(value) },
        "invalid domain \(value)",
        matching: { error in
            if case .invalidDomain = error { return true }
            return false
        }
    )
}

private func testDefaultBlockContainsAllDomains() throws {
    try checkEqual(
        FocusVaultBlocker.defaultDomains,
        FocusVaultBlocker.youtubeDomains,
        "the default YouTube blocker domains changed"
    )
    try withFixture { hostsFile in
        let blocker = try FocusVaultBlocker(hostsFileURL: hostsFile)
        let changed = try blocker.block()
        try check(changed, "first block should change the hosts file")
        let contents = try read(hostsFile)
        try check(contents.contains(FocusVaultBlocker.beginMarker), "Vaulty begin marker is missing")
        try check(contents.contains(FocusVaultBlocker.endMarker), "Vaulty end marker is missing")
        try check(contents.contains("Vault in and get work done"), "focus tagline is missing from the managed section")
        for domain in FocusVaultBlocker.defaultDomains {
            try check(contents.contains("0.0.0.0 \(domain)"), "missing default domain: \(domain)")
        }
        for domain in ["tiktok.com", "instagram.com", "facebook.com"] {
            try check(!contents.contains("0.0.0.0 \(domain)"), "short-form domain leaked into YouTube blocker: \(domain)")
        }
    }
}

private func testShortFormPolicyCoversRequestedPlatforms() throws {
    let samples: [(String, ShortFormPlatform)] = [
        ("https://www.tiktok.com/@creator/video/123", .tiktok),
        ("https://www.instagram.com/reel/123/", .instagram),
        ("https://www.youtube.com/shorts/abc123", .youtube),
        ("https://www.facebook.com/reels/videos/123", .facebook),
        ("https://fb.watch/abc123/", .facebook)
    ]

    for (url, platform) in samples {
        let decision = ShortFormPolicy.decision(for: url)
        try checkEqual(decision.state, .blocked, "short-form URL was not blocked: \(url)")
        try checkEqual(decision.platform, platform, "wrong short-form platform for \(url)")
        try check(ShortFormPolicy.isShortFormURL(url), "short-form URL was not recognized: \(url)")
    }

    try checkEqual(
        ShortFormPolicy.decision(for: "https://www.youtube.com/watch?v=abc").state,
        .notShortForm,
        "regular YouTube watch URL was classified as Shorts"
    )
    try checkEqual(
        ShortFormPolicy.decision(for: "https://www.instagram.com/p/123/").state,
        .notShortForm,
        "regular Instagram post URL was classified as a Reel"
    )
    try checkEqual(
        ShortFormPolicy.decision(for: "https://www.facebook.com/groups/work").state,
        .notShortForm,
        "regular Facebook URL was classified as a Reel"
    )
    try checkEqual(
        ShortFormPolicy.decision(for: "https://example.com/reel/123").state,
        .outside,
        "unrelated host was treated as short-form"
    )
}

private func testShortFormBlockerCoversRequestedHosts() throws {
    try withFixture { hostsFile in
        let blocker = try ShortFormBlocker(hostsFileURL: hostsFile)
        try check(!(try blocker.isBlocked()), "fresh short-form vault is incorrectly blocked")
        try check(try blocker.block(), "short-form block did not change the hosts file")
        try check(try blocker.isBlocked(), "short-form vault did not report complete coverage")

        let contents = try read(hostsFile)
        try check(contents.contains(ShortFormBlocker.beginMarker), "short-form begin marker is missing")
        try check(contents.contains(ShortFormBlocker.endMarker), "short-form end marker is missing")
        for platform in ShortFormPlatform.allCases {
            for domain in ShortFormPolicy.hosts(for: platform) {
                try check(
                    contents.contains("0.0.0.0 \(domain)"),
                    "missing \(platform.displayName) host mapping: \(domain)"
                )
            }
        }

        try check(try blocker.unblock(), "short-form vault did not unblock")
        try checkEqual(try read(hostsFile), defaultFixtureContents, "short-form unblock damaged existing hosts content")
    }
}

private func testShortFormBlockerIsIndependentFromYouTubeBlocker() throws {
    try withFixture { hostsFile in
        let youtubeOnly = try FocusVaultBlocker(
            hostsFileURL: hostsFile,
            domains: FocusVaultBlocker.youtubeDomains
        )
        let shortForm = try ShortFormBlocker(hostsFileURL: hostsFile)

        try check(try youtubeOnly.block(), "YouTube-only fixture block failed")
        try check(try youtubeOnly.isBlocked(), "YouTube blocker did not report its own section")
        try check(!(try shortForm.isBlocked()), "YouTube block was mistaken for short-form coverage")

        try check(try shortForm.block(), "separate short-form block did not change the hosts file")
        try check(try shortForm.isBlocked(), "short-form block is incomplete")
        try check(try youtubeOnly.isBlocked(), "short-form block damaged the YouTube blocker")

        try check(try shortForm.unblock(), "short-form block did not unblock independently")
        try check(!(try shortForm.isBlocked()), "short-form block remained after independent unblock")
        try check(try youtubeOnly.isBlocked(), "short-form unblock damaged the YouTube blocker")

        try check(try youtubeOnly.unblock(), "YouTube block did not unblock independently")
        try checkEqual(try read(hostsFile), defaultFixtureContents, "independent block cycles damaged existing hosts content")
    }
}

private func testDefaultYouTubeChannelAllowlist() throws {
    try checkEqual(YouTubeChannelDefaults.channels.count, 2, "unexpected default YouTube channel count")
    try checkEqual(YouTubeChannelDefaults.channels[0].displayHandle, "@AlexHormozi", "Alex Hormozi default handle changed")
    try checkEqual(YouTubeChannelDefaults.channels[0].channelID, "UCUyDOdBWhC1MCxEjC46d-zw", "Alex Hormozi default ID changed")
    try checkEqual(YouTubeChannelDefaults.channels[1].displayHandle, "@MoreMozi", "MoreMozi default handle changed")
    try checkEqual(YouTubeChannelDefaults.channels[1].channelID, "UCrvchO1h6lWZAuGaa1LqX9Q", "MoreMozi default ID changed")
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

private func testEmptyExistingFile() throws {
    try withFixture(initial: "") { hostsFile in
        let blocker = try FocusVaultBlocker(hostsFileURL: hostsFile)
        _ = try blocker.block()
        try check(try blocker.isBlocked(), "empty file was not marked blocked")
        try check(try blocker.unblock(), "empty file did not unblock")
        try checkEqual(try read(hostsFile), "", "empty file did not return to empty")
    }
}

private func testMissingHostsFileCreated() throws {
    try withMissingHostsFile { fixture in
        let blocker = try FocusVaultBlocker(hostsFileURL: fixture.hostsFile)
        _ = try blocker.block()
        try check(FileManager.default.fileExists(atPath: fixture.hostsFile.path), "missing hosts file was not created")
        try check(try blocker.isBlocked(), "created hosts file is not blocked")
    }
}

private func testPreservesNoFinalNewline() throws {
    let original = "# preserved\n127.0.0.1 localhost"
    try withFixture(initial: original) { hostsFile in
        let blocker = try FocusVaultBlocker(hostsFileURL: hostsFile)
        _ = try blocker.block()
        try check(try blocker.unblock(), "no-newline file did not unblock")
        try checkEqual(try read(hostsFile), original, "no-newline content was not preserved")
    }
}

private func testPreservesExistingFinalNewline() throws {
    let original = "# preserved\n127.0.0.1 localhost\n"
    try withFixture(initial: original) { hostsFile in
        let blocker = try FocusVaultBlocker(hostsFileURL: hostsFile)
        _ = try blocker.block()
        _ = try blocker.unblock()
        try checkEqual(try read(hostsFile), original, "final newline was not preserved")
    }
}

private func testPreservesUnicodeComments() throws {
    let original = "# my focus notes ✨\n127.0.0.1 localhost\n"
    try withFixture(initial: original) { hostsFile in
        let blocker = try FocusVaultBlocker(hostsFileURL: hostsFile)
        _ = try blocker.block()
        try check((try read(hostsFile)).contains("my focus notes ✨"), "Unicode comments were lost")
        _ = try blocker.unblock()
        try checkEqual(try read(hostsFile), original, "Unicode comments did not round-trip")
    }
}

private func testBlockIsIdempotent() throws {
    try withFixture { hostsFile in
        let blocker = try FocusVaultBlocker(hostsFileURL: hostsFile)
        try check(try blocker.block(), "first block should change the file")
        let first = try read(hostsFile)
        try check(!(try blocker.block()), "second block should be idempotent")
        try checkEqual(try read(hostsFile), first, "second block changed the file")
        try checkEqual(first.components(separatedBy: FocusVaultBlocker.beginMarker).count, 2, "duplicate FocusVault block was written")
    }
}

private func testUnblockIsIdempotent() throws {
    try withFixture { hostsFile in
        let blocker = try FocusVaultBlocker(hostsFileURL: hostsFile)
        try check(!(try blocker.unblock()), "unblock without a block should do nothing")
        _ = try blocker.block()
        try check(try blocker.unblock(), "first unblock should change the file")
        try check(!(try blocker.unblock()), "second unblock should be idempotent")
    }
}

private func testUnblockRestoresExactContent() throws {
    let original = "# first\n127.0.0.1 localhost\n# last\n"
    try withFixture(initial: original) { hostsFile in
        let blocker = try FocusVaultBlocker(hostsFileURL: hostsFile)
        _ = try blocker.block()
        _ = try blocker.unblock()
        try checkEqual(try read(hostsFile), original, "unblock did not restore exact content")
    }
}

private func testStatusUnblocked() throws {
    try withFixture { hostsFile in
        let blocker = try FocusVaultBlocker(hostsFileURL: hostsFile)
        try check(!(try blocker.isBlocked()), "fresh hosts file is incorrectly blocked")
    }
}

private func testStatusBlocked() throws {
    try withFixture { hostsFile in
        let blocker = try FocusVaultBlocker(hostsFileURL: hostsFile)
        _ = try blocker.block()
        try check(try blocker.isBlocked(), "blocked hosts file reports unblocked")
    }
}

private func testCustomDomains() throws {
    try withFixture { hostsFile in
        let blocker = try FocusVaultBlocker(
            hostsFileURL: hostsFile,
            domains: ["youtube.com", "reddit.com"]
        )
        _ = try blocker.block()
        let contents = try read(hostsFile)
        try check(contents.contains("0.0.0.0 youtube.com"), "custom YouTube domain is missing")
        try check(contents.contains("0.0.0.0 reddit.com"), "custom Reddit domain is missing")
        try check(!contents.contains("0.0.0.0 youtu.be"), "default domain leaked into custom block")
    }
}

private func testCustomDomainOrderAndDeduplication() throws {
    let blocker = try FocusVaultBlocker(
        domains: ["Example.com", "example.com", "EXAMPLE.org", "example.com"]
    )
    try checkEqual(blocker.domains, ["example.com", "example.org"], "domains were not normalized and deduplicated in order")
}

private func testHTTPSNormalization() throws {
    try checkEqual(
        try FocusVaultBlocker.normalizeDomain("HTTPS://Example.COM:8443/path?q=1"),
        "example.com",
        "HTTPS URL was not normalized"
    )
}

private func testBarePathNormalization() throws {
    try checkEqual(
        try FocusVaultBlocker.normalizeDomain("example.com/watch"),
        "example.com",
        "hostname path was not stripped"
    )
}

private func testCaseAndDotNormalization() throws {
    try checkEqual(
        try FocusVaultBlocker.normalizeDomain("...WWW.Example.COM..."),
        "www.example.com",
        "case and dots were not normalized"
    )
}

private func testCRLFBlockUsesCRLF() throws {
    let original = "# preserved\r\n127.0.0.1 localhost\r\n"
    try withFixture(initial: original) { hostsFile in
        let blocker = try FocusVaultBlocker(hostsFileURL: hostsFile)
        _ = try blocker.block()
        let contents = try read(hostsFile)
        try check(contents.contains("# BEGIN VAULTY MANAGED BLOCK\r\n"), "CRLF marker line was not preserved")
        try check(!contents.replacingOccurrences(of: "\r\n", with: "").contains("\n"), "mixed line endings were introduced")
    }
}

private func testCRLFUnblockPreservesExactContent() throws {
    let original = "# preserved\r\n127.0.0.1 localhost\r\n"
    try withFixture(initial: original) { hostsFile in
        let blocker = try FocusVaultBlocker(hostsFileURL: hostsFile)
        _ = try blocker.block()
        _ = try blocker.unblock()
        try checkEqual(try read(hostsFile), original, "CRLF content did not round-trip")
    }
}

private func testFocusVaultBlockMigrates() throws {
    let legacy = [
        FocusVaultBlocker.focusVaultBeginMarker,
        "# old FocusVault block",
        "0.0.0.0 youtube.com",
        FocusVaultBlocker.focusVaultEndMarker,
        ""
    ].joined(separator: "\n")
    try withFixture(initial: legacy) { hostsFile in
        let blocker = try FocusVaultBlocker(hostsFileURL: hostsFile)
        try check(try blocker.isBlocked(), "FocusVault block was not detected")
        try check(try blocker.block(), "FocusVault block was not replaced")
        let contents = try read(hostsFile)
        try check(contents.contains(FocusVaultBlocker.beginMarker), "FocusVault block was not migrated")
        try check(!contents.contains(FocusVaultBlocker.focusVaultBeginMarker), "FocusVault marker remains after migration")
    }
}

private func testFocusVaultUnblock() throws {
    let legacy = "# before\n\(FocusVaultBlocker.focusVaultBeginMarker)\n0.0.0.0 youtube.com\n\(FocusVaultBlocker.focusVaultEndMarker)\n# after\n"
    try withFixture(initial: legacy) { hostsFile in
        let blocker = try FocusVaultBlocker(hostsFileURL: hostsFile)
        try check(try blocker.unblock(), "FocusVault block was not removed")
        try checkEqual(try read(hostsFile), "# before\n# after\n", "FocusVault unblock damaged surrounding content")
    }
}

private func testLegacyBlockMigrates() throws {
    let legacy = [
        FocusVaultBlocker.legacyBeginMarker,
        "# legacy block",
        "0.0.0.0 youtube.com",
        FocusVaultBlocker.legacyEndMarker,
        ""
    ].joined(separator: "\n")
    try withFixture(initial: legacy) { hostsFile in
        let blocker = try FocusVaultBlocker(hostsFileURL: hostsFile)
        try check(try blocker.isBlocked(), "legacy block was not detected")
        _ = try blocker.block()
        let contents = try read(hostsFile)
        try check(contents.contains(FocusVaultBlocker.beginMarker), "legacy block was not migrated")
        try check(!contents.contains(FocusVaultBlocker.legacyBeginMarker), "legacy marker remains after migration")
    }
}

private func testLegacyUnblock() throws {
    let legacy = "# before\n\(FocusVaultBlocker.legacyBeginMarker)\n0.0.0.0 youtube.com\n\(FocusVaultBlocker.legacyEndMarker)\n# after\n"
    try withFixture(initial: legacy) { hostsFile in
        let blocker = try FocusVaultBlocker(hostsFileURL: hostsFile)
        try check(try blocker.unblock(), "legacy block was not removed")
        try checkEqual(try read(hostsFile), "# before\n# after\n", "legacy unblock damaged surrounding content")
    }
}

private func testCRLFLegacyMigration() throws {
    let legacy = [
        FocusVaultBlocker.legacyBeginMarker,
        "0.0.0.0 youtube.com",
        FocusVaultBlocker.legacyEndMarker,
        ""
    ].joined(separator: "\r\n")
    try withFixture(initial: legacy) { hostsFile in
        let blocker = try FocusVaultBlocker(hostsFileURL: hostsFile)
        _ = try blocker.block()
        let contents = try read(hostsFile)
        try check(contents.contains(FocusVaultBlocker.beginMarker + "\r\n"), "CRLF legacy block was not migrated")
        try check(!contents.contains(FocusVaultBlocker.legacyBeginMarker), "CRLF legacy marker remains")
    }
}

private func testMarkerTextInsideCommentIsIgnored() throws {
    let original = "# Mention \(FocusVaultBlocker.beginMarker) in documentation\n# and \(FocusVaultBlocker.endMarker) too\n"
    try withFixture(initial: original) { hostsFile in
        let blocker = try FocusVaultBlocker(hostsFileURL: hostsFile)
        try check(!(try blocker.isBlocked()), "marker text inside a comment was treated as active")
        try check(!(try blocker.unblock()), "comment marker text was removed")
        try checkEqual(try read(hostsFile), original, "comment marker text changed")
    }
}

private func testLeadingWhitespaceMarkerIsIgnored() throws {
    let original = "  \(FocusVaultBlocker.beginMarker)\n  \(FocusVaultBlocker.endMarker)\n"
    try withFixture(initial: original) { hostsFile in
        let blocker = try FocusVaultBlocker(hostsFileURL: hostsFile)
        try check(!(try blocker.isBlocked()), "indented marker was treated as managed")
        try check(!(try blocker.unblock()), "indented marker was removed")
    }
}

private func testSimilarMarkerIsIgnored() throws {
    let original = "\(FocusVaultBlocker.beginMarker) extra\n\(FocusVaultBlocker.endMarker) extra\n"
    try withFixture(initial: original) { hostsFile in
        let blocker = try FocusVaultBlocker(hostsFileURL: hostsFile)
        try check(!(try blocker.isBlocked()), "similar marker was treated as managed")
        try check(!(try blocker.unblock()), "similar marker was removed")
    }
}

private func testMalformedBeginOnly() throws {
    let contents = "\(FocusVaultBlocker.beginMarker)\n0.0.0.0 youtube.com\n"
    try withFixture(initial: contents) { hostsFile in
        let blocker = try FocusVaultBlocker(hostsFileURL: hostsFile)
        try expectFocusVaultError({ _ = try blocker.block() }, "begin-only section")
        try expectFocusVaultError({ _ = try blocker.unblock() }, "begin-only removal")
    }
}

private func testMalformedEndOnly() throws {
    let contents = "0.0.0.0 youtube.com\n\(FocusVaultBlocker.endMarker)\n"
    try withFixture(initial: contents) { hostsFile in
        let blocker = try FocusVaultBlocker(hostsFileURL: hostsFile)
        try expectFocusVaultError({ _ = try blocker.block() }, "end-only section")
    }
}

private func testReversedMarkers() throws {
    let contents = "\(FocusVaultBlocker.endMarker)\n\(FocusVaultBlocker.beginMarker)\n"
    try withFixture(initial: contents) { hostsFile in
        let blocker = try FocusVaultBlocker(hostsFileURL: hostsFile)
        try expectFocusVaultError({ _ = try blocker.block() }, "reversed markers")
    }
}

private func testMismatchedMarkers() throws {
    let contents = "\(FocusVaultBlocker.beginMarker)\n\(FocusVaultBlocker.legacyEndMarker)\n"
    try withFixture(initial: contents) { hostsFile in
        let blocker = try FocusVaultBlocker(hostsFileURL: hostsFile)
        try expectFocusVaultError({ _ = try blocker.block() }, "mismatched marker families")
    }
}

private func testDuplicateManagedBlocks() throws {
    let one = FocusVaultBlocker.beginMarker + "\n" + FocusVaultBlocker.endMarker + "\n"
    try withFixture(initial: one + one) { hostsFile in
        let blocker = try FocusVaultBlocker(hostsFileURL: hostsFile)
        try expectFocusVaultError({ _ = try blocker.block() }, "duplicate managed blocks")
    }
}

private func testFocusAndLegacyTogether() throws {
    let contents = "\(FocusVaultBlocker.beginMarker)\n\(FocusVaultBlocker.endMarker)\n\(FocusVaultBlocker.legacyBeginMarker)\n\(FocusVaultBlocker.legacyEndMarker)\n"
    try withFixture(initial: contents) { hostsFile in
        let blocker = try FocusVaultBlocker(hostsFileURL: hostsFile)
        try expectFocusVaultError({ _ = try blocker.unblock() }, "mixed managed blocks")
    }
}

private func testNestedMarkers() throws {
    let contents = "\(FocusVaultBlocker.beginMarker)\n\(FocusVaultBlocker.beginMarker)\n\(FocusVaultBlocker.endMarker)\n"
    try withFixture(initial: contents) { hostsFile in
        let blocker = try FocusVaultBlocker(hostsFileURL: hostsFile)
        try expectFocusVaultError({ _ = try blocker.block() }, "nested markers")
    }
}

private func testExternalContentInsideBlockIsReplaced() throws {
    let contents = "\(FocusVaultBlocker.beginMarker)\nuser edited this\n\(FocusVaultBlocker.endMarker)\n"
    try withFixture(initial: contents) { hostsFile in
        let blocker = try FocusVaultBlocker(hostsFileURL: hostsFile)
        _ = try blocker.block()
        let result = try read(hostsFile)
        try check(!result.contains("user edited this"), "stale managed content survived replacement")
        try check(result.contains("0.0.0.0 youtube.com"), "replacement block is incomplete")
    }
}

private func testRejectEmptyDomain() throws {
    try expectFocusVaultError({ _ = try FocusVaultBlocker.normalizeDomain("") }, "empty domain") { error in
        if case .emptyDomain = error { return true }
        return false
    }
}

private func testRejectWhitespaceDomain() throws {
    try expectInvalidDomain(" youtube .com ")
}

private func testRejectWildcard() throws {
    try expectInvalidDomain("*.youtube.com")
}

private func testRejectCommentInjection() throws {
    try expectInvalidDomain("youtube.com#comment")
}

private func testRejectNewlineInjection() throws {
    try expectInvalidDomain("youtube.com\n0.0.0.0 evil.com")
}

private func testRejectIPv4Literal() throws {
    try expectInvalidDomain("127.0.0.1")
}

private func testRejectIPv6Literal() throws {
    try expectInvalidDomain("[::1]")
}

private func testRejectEmptyLabel() throws {
    try expectInvalidDomain("youtube..com")
}

private func testRejectHyphenLabel() throws {
    try expectInvalidDomain("-youtube.com")
    try expectInvalidDomain("youtube-.com")
}

private func testRejectLongLabel() throws {
    try expectInvalidDomain(String(repeating: "a", count: 64) + ".com")
}

private func testRejectLongDomain() throws {
    let longDomain = (0..<60).map { _ in "aaaa" }.joined(separator: ".")
    try expectInvalidDomain(longDomain)
}

private func testRejectUnicodeHostname() throws {
    try expectInvalidDomain("münich.example")
}

private func testAcceptLocalhost() throws {
    try checkEqual(try FocusVaultBlocker.normalizeDomain("localhost"), "localhost", "localhost should be accepted")
}

private func testAcceptPunycode() throws {
    try checkEqual(try FocusVaultBlocker.normalizeDomain("xn--mnich-kva.example"), "xn--mnich-kva.example", "punycode should be accepted")
}

private func testAcceptHTTPSPort() throws {
    try checkEqual(try FocusVaultBlocker.normalizeDomain("https://example.com:443"), "example.com", "HTTPS port should be normalized")
}

private func testMissingParentWriteError() throws {
    let directory = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let hostsFile = directory.appendingPathComponent("missing/hosts")
    let blocker = try FocusVaultBlocker(hostsFileURL: hostsFile)
    try expectFocusVaultError({ _ = try blocker.block() }, "missing parent directory") { error in
        if case .unableToWrite = error { return true }
        return false
    }
}

private func testDirectoryReadError() throws {
    let directory = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let blocker = try FocusVaultBlocker(hostsFileURL: directory)
    try expectFocusVaultError({ _ = try blocker.block() }, "directory used as hosts file") { error in
        if case .unableToRead = error { return true }
        return false
    }
}

private func testPermissionsPreserved() throws {
    try withFixture { hostsFile in
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o600)],
            ofItemAtPath: hostsFile.path
        )
        let blocker = try FocusVaultBlocker(hostsFileURL: hostsFile)
        _ = try blocker.block()
        let attributes = try FileManager.default.attributesOfItem(atPath: hostsFile.path)
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue
        try checkEqual(permissions, 0o600, "file permissions changed during atomic write")
    }
}

private func testLargeHostsFile() throws {
    let original = (0..<2_000).map { "127.0.0.1 host\($0).example" }.joined(separator: "\n") + "\n"
    try withFixture(initial: original) { hostsFile in
        let blocker = try FocusVaultBlocker(hostsFileURL: hostsFile)
        _ = try blocker.block()
        try check((try read(hostsFile)).contains("127.0.0.1 host1999.example"), "large hosts file was truncated")
        _ = try blocker.unblock()
        try checkEqual(try read(hostsFile), original, "large hosts file did not round-trip")
    }
}

private func testRepeatedCycles() throws {
    try withFixture { hostsFile in
        let blocker = try FocusVaultBlocker(hostsFileURL: hostsFile)
        for _ in 0..<100 {
            try check(try blocker.block(), "cycle block was not a change")
            try check(try blocker.isBlocked(), "cycle block was not detected")
            try check(try blocker.unblock(), "cycle unblock was not a change")
            try check(!(try blocker.isBlocked()), "cycle unblock was not detected")
        }
        try checkEqual(try read(hostsFile), defaultFixtureContents, "repeated cycles drifted the file")
    }
}

private func testCustomBlockThenDefaultUnblock() throws {
    try withFixture { hostsFile in
        let custom = try FocusVaultBlocker(hostsFileURL: hostsFile, domains: ["youtube.com", "reddit.com"])
        _ = try custom.block()
        let defaults = try FocusVaultBlocker(hostsFileURL: hostsFile)
        try check(try defaults.unblock(), "default blocker could not remove custom block")
        try checkEqual(try read(hostsFile), defaultFixtureContents, "custom block was not fully removed")
    }
}

private func testUnblockWithoutBlockDoesNotChange() throws {
    let original = "# leave this alone\n"
    try withFixture(initial: original) { hostsFile in
        let blocker = try FocusVaultBlocker(hostsFileURL: hostsFile)
        try check(!(try blocker.unblock()), "unblock changed an unmanaged file")
        try checkEqual(try read(hostsFile), original, "unmanaged file changed")
    }
}

private func testPrefixAndSuffixRemain() throws {
    let managed = "\(FocusVaultBlocker.beginMarker)\n0.0.0.0 youtube.com\n\(FocusVaultBlocker.endMarker)\n"
    let original = "# before\n" + managed + "# after\n"
    try withFixture(initial: original) { hostsFile in
        let blocker = try FocusVaultBlocker(hostsFileURL: hostsFile)
        _ = try blocker.unblock()
        try checkEqual(try read(hostsFile), "# before\n# after\n", "prefix or suffix was removed")
    }
}

private func testStatusMalformedThrows() throws {
    let original = "\(FocusVaultBlocker.beginMarker)\n"
    try withFixture(initial: original) { hostsFile in
        let blocker = try FocusVaultBlocker(hostsFileURL: hostsFile)
        try expectFocusVaultError({ _ = try blocker.isBlocked() }, "status on malformed section")
    }
}

private func testEmptyCustomDomainListThrows() throws {
    try expectFocusVaultError({ _ = try FocusVaultBlocker(domains: []) }, "empty custom domain list") { error in
        if case .emptyDomain = error { return true }
        return false
    }
}

private func testSleepCalculatorBedtimes() throws {
    let calendar = testCalendar()
    let wakeTime = testDate(2026, 8, 24, 7, 0)
    let results = SleepCalculator.bedtimes(for: wakeTime, calendar: calendar)

    try checkEqual(results.map(\.cycles), [6, 5, 4], "sleep cycle recommendations changed order")
    try checkEqual(results.map(\.sleepMinutes), [540, 450, 360], "sleep durations are wrong")
    try checkEqual(
        results[0].time,
        testDate(2026, 8, 23, 21, 46),
        "six-cycle bedtime did not include sleep latency"
    )
    try checkEqual(
        results[2].time,
        testDate(2026, 8, 24, 0, 46),
        "four-cycle bedtime did not cross midnight correctly"
    )
}

private func testSleepCalculatorWakeTimesAndFiltering() throws {
    let calendar = testCalendar()
    let bedtime = testDate(2026, 8, 23, 22, 0)
    let results = SleepCalculator.recommendations(
        direction: .bedtime,
        time: bedtime,
        calendar: calendar,
        cycleCounts: [6, 6, 0, 13, 3]
    )

    try checkEqual(results.map(\.cycles), [6, 3], "invalid or duplicate sleep cycles were not filtered")
    try checkEqual(results[0].time, testDate(2026, 8, 24, 7, 14), "six-cycle wake time is wrong")
    try checkEqual(results[1].time, testDate(2026, 8, 24, 2, 44), "three-cycle wake time is wrong")
    try checkEqual(
        SleepCalculator.recommendations(direction: .wakeTime, time: bedtime, calendar: calendar),
        SleepCalculator.bedtimes(for: bedtime, calendar: calendar),
        "direction recommendation did not use bedtime calculation"
    )
}

private func testTaskClockAcceptsExactEstimate() throws {
    let clock = try FocusTaskClock(minutes: 40)
    try checkEqual(clock.durationSeconds, 2_400, "task clock duration is not exact")
    try checkEqual(clock.remainingWholeSeconds, 2_400, "task clock initial remainder is wrong")
    try checkEqual(clock.state, .ready, "new task clock is not ready")
}

private func testTaskClockRejectsInvalidEstimate() throws {
    for minutes in [0, -1, 241] {
        do {
            _ = try FocusTaskClock(minutes: minutes)
            throw SelfTestFailure(message: "invalid task estimate was accepted: \(minutes)")
        } catch let error as FocusTaskClockError {
            try checkEqual(error, .invalidDuration, "wrong task clock error for \(minutes) minutes")
        }
    }
}

private func testTaskClockPausePreservesRemainder() throws {
    let start = Date(timeIntervalSinceReferenceDate: 10_000)
    let pauseDate = start.addingTimeInterval(605)
    var clock = try FocusTaskClock(minutes: 40)

    try check(clock.start(at: start), "task clock did not start")
    clock.update(at: pauseDate)
    try check(clock.pause(at: pauseDate), "task clock did not pause")
    try checkEqual(clock.state, .paused, "task clock is not paused")
    try check(abs(clock.remainingSeconds - 1_795) < 0.0001, "pause remainder is not exact")

    let pausedRemainder = clock.remainingSeconds
    clock.update(at: pauseDate.addingTimeInterval(900))
    try checkEqual(clock.remainingSeconds, pausedRemainder, "paused time reduced the task clock")
}

private func testTaskClockResumesCompletesAndStops() throws {
    let start = Date(timeIntervalSinceReferenceDate: 20_000)
    var clock = try FocusTaskClock(minutes: 1)

    try check(clock.start(at: start), "one-minute task clock did not start")
    let pauseDate = start.addingTimeInterval(12.5)
    try check(clock.pause(at: pauseDate), "one-minute task clock did not pause")
    let pausedRemainder = clock.remainingSeconds
    try check(clock.resume(at: pauseDate.addingTimeInterval(90)), "task clock did not resume")
    clock.update(at: pauseDate.addingTimeInterval(90 + pausedRemainder + 0.1))
    try checkEqual(clock.state, .completed, "task clock did not complete at zero")
    try checkEqual(clock.remainingWholeSeconds, 0, "completed task clock has remaining time")
    try checkEqual(clock.progress, 1, "completed task clock is not at full progress")

    var stoppedClock = try FocusTaskClock(minutes: 10)
    try check(stoppedClock.start(at: start), "stoppable task clock did not start")
    stoppedClock.update(at: start.addingTimeInterval(30))
    try check(stoppedClock.stop(at: start.addingTimeInterval(30)), "task clock did not stop")
    try checkEqual(stoppedClock.state, .ready, "stopped task clock did not reset to ready")
    try checkEqual(stoppedClock.remainingWholeSeconds, 600, "stopped task clock did not reset its estimate")
}

private func testSignalShiftTransformsCoordinates() throws {
    let point = SignalGridPoint(row: 0, column: 1)
    try checkEqual(
        SignalTransform.unchanged.apply(to: point, gridSize: 4),
        point,
        "practice-room identity transform changed the path"
    )
    try checkEqual(
        SignalTransform.rotateClockwise.apply(to: point, gridSize: 4),
        SignalGridPoint(row: 1, column: 3),
        "clockwise mental rotation is wrong"
    )
    try checkEqual(
        SignalTransform.rotateCounterClockwise.apply(to: point, gridSize: 4),
        SignalGridPoint(row: 2, column: 0),
        "counter-clockwise mental rotation is wrong"
    )
    try checkEqual(
        SignalTransform.mirrorHorizontally.apply(to: point, gridSize: 4),
        SignalGridPoint(row: 0, column: 2),
        "horizontal mirror is wrong"
    )
}

private func testSignalShiftDifficultyProgression() throws {
    var generator = SignalShiftGenerator(seed: 42)
    let first = generator.makePuzzle(level: 1)
    let second = generator.makePuzzle(level: 2)
    let third = generator.makePuzzle(level: 3)

    try checkEqual(first.sequence.count, 3, "practice room should contain three signals")
    try checkEqual(first.transform, .unchanged, "practice room should not transform the path")
    try check(!first.reverseOrder, "practice room should preserve order")
    try checkEqual(second.sequence.count, 4, "level two should contain four signals")
    try checkEqual(second.transform, .mirrorHorizontally, "level two transform changed")
    try check(!second.reverseOrder, "level two should preserve order")
    try checkEqual(third.sequence.count, 4, "level three should contain four signals")
    try checkEqual(third.transform, .rotateClockwise, "level three transform changed")
    try check(!third.reverseOrder, "level three should preserve order")
    try checkEqual(Set(first.sequence).count, first.sequence.count, "a puzzle repeated a signal cell")
    try check(zip(first.sequence, first.sequence.dropFirst()).allSatisfy { pair in
        let (left, right) = pair
        return abs(left.row - right.row) + abs(left.column - right.column) == 1
    }, "practice-room signals should form a connected path")
}

private func testSignalShiftRequiresThreeCompletedRounds() throws {
    var run = SignalShiftRun(seed: 7)
    try checkEqual(run.submit(run.puzzle.expectedSequence), .advanced(nextLevel: 2), "first solved round did not advance")
    try checkEqual(run.submit(run.puzzle.expectedSequence), .advanced(nextLevel: 3), "second solved round did not advance")
    try checkEqual(run.submit(run.puzzle.expectedSequence), .completed, "third solved round did not complete")
    try checkEqual(run.livesRemaining, 3, "correct rounds consumed lives")
}

private func testSignalShiftPracticeRoomCostsNoLives() throws {
    var run = SignalShiftRun(seed: 99)
    let wrong = [SignalGridPoint(row: -1, column: -1)]

    try checkEqual(run.submit(wrong), .retry(livesRemaining: 3), "practice mistake consumed a life")
    try checkEqual(run.livesRemaining, 3, "practice room reduced lives")
    try checkEqual(run.level, 1, "practice retry advanced the room")
}

private func testSignalShiftThreeLivesLockOut() throws {
    var run = SignalShiftRun(seed: 99)
    let wrong = [SignalGridPoint(row: -1, column: -1)]
    try checkEqual(run.submit(run.puzzle.expectedSequence), .advanced(nextLevel: 2), "could not leave practice room")

    try checkEqual(run.submit(wrong), .retry(livesRemaining: 2), "first scored mistake did not consume one life")
    try checkEqual(run.submit(wrong), .retry(livesRemaining: 1), "second mistake did not consume one life")
    try checkEqual(run.submit(wrong), .lockedOut, "third mistake did not require a fresh password attempt")
    try checkEqual(run.livesRemaining, 0, "lockout retained a life")
}

private func testGridShotScoringAndTargetRelocation() throws {
    var run = GridShotRun(seed: 123)
    try checkEqual(run.targets.count, 3, "Grid Shot did not start with three targets")
    guard let firstTarget = run.targets.first else {
        throw SelfTestFailure(message: "Grid Shot started without a target")
    }
    try checkEqual(
        run.tap(at: firstTarget.point),
        .hit(targetID: firstTarget.id),
        "Grid Shot target click was not a hit"
    )
    try checkEqual(run.score, 1, "Grid Shot hit did not add one point")
    try checkEqual(run.targets.count, 3, "Grid Shot did not keep three targets")
    try check(
        run.targets.first(where: { $0.id == firstTarget.id })?.point != firstTarget.point,
        "Grid Shot hit target did not relocate"
    )

    try checkEqual(
        run.tap(at: GridShotPoint(x: 0, y: 0)),
        .miss,
        "Grid Shot empty arena click was treated as a hit"
    )
    try checkEqual(run.score, 0, "Grid Shot miss did not remove one point")
}

private func testGridShotHardTargetIsThirty() throws {
    var run = GridShotRun(seed: 456)
    for _ in 0..<GridShotRun.targetScore {
        guard let target = run.targets.first else {
            throw SelfTestFailure(message: "Grid Shot lost every target")
        }
        try checkEqual(
            run.tap(at: target.point),
            .hit(targetID: target.id),
            "Grid Shot target click was not a hit"
        )
    }
    try checkEqual(GridShotRun.durationSeconds, 10, "Grid Shot duration changed")
    try checkEqual(GridShotRun.targetCount, 3, "Grid Shot target count changed")
    try checkEqual(GridShotRun.targetRadius, 50, "Grid Shot aim radius changed")
    try checkEqual(run.score, 30, "Grid Shot hard target was not 30")
    try check(run.hasReachedTarget, "Grid Shot did not pass at score 30")
}

private func testTypingSprintMonkeytypeCompletion() throws {
    let prompt = TypingSprint.prompt(seed: 42)
    try checkEqual(prompt, TypingSprint.prompt(seed: 42), "typing prompt generation is not deterministic")
    try checkEqual(prompt.split(separator: " ").count, TypingSprint.wordCount, "typing prompt word count changed")

    let success = TypingSprint.evaluate(typed: prompt, target: prompt, elapsedSeconds: 120)
    try check(success.succeeded, "exact Monkeytype-style completion did not pass immediately")
    try checkEqual(success.accuracy, 1, "exact typing sprint accuracy is not 100 percent")

    var incorrect = prompt
    incorrect.removeLast()
    incorrect.append("x")
    let mistake = TypingSprint.evaluate(typed: incorrect, target: prompt, elapsedSeconds: 12)
    try check(!mistake.succeeded, "typing sprint passed incorrect text")
}

private func testRootOwnedAdminUnlockPolicy() throws {
    let request = YouTubeGuardRequest(
        command: .unlock,
        authorization: YouTubeGuardPaths.rootAuthorizedRequestMarker
    )
    try check(
        request.allowsRootOwnedAuthorization(ownerID: 0, posixPermissions: 0o600),
        "root-owned 0600 administrator unlock request was rejected"
    )
    try check(
        !request.allowsRootOwnedAuthorization(ownerID: 501, posixPermissions: 0o600),
        "user-owned request was allowed to use root authorization"
    )
    try check(
        !request.allowsRootOwnedAuthorization(ownerID: 0, posixPermissions: 0o644),
        "group/world-readable request was allowed to use root authorization"
    )
    let ordinary = YouTubeGuardRequest(command: .unlock, authorization: "not-the-root-marker")
    try check(
        !ordinary.allowsRootOwnedAuthorization(ownerID: 0, posixPermissions: 0o600),
        "ordinary token was mistaken for a root-authorized request"
    )
}

private func testUnlockChallengeKindsRemainComplete() throws {
    try checkEqual(
        UnlockChallengeKind.allCases,
        [.signalShift, .gridShot, .typingSprint],
        "known challenge kinds changed unexpectedly"
    )
    try checkEqual(
        UnlockChallengeKind.requiredRotation,
        [.gridShot, .typingSprint],
        "required unlock rotation should contain only Grid Shot and Typing Sprint"
    )
    try checkEqual(
        UnlockChallengeKind.taskHubChoices,
        [.gridShot, .typingSprint, .signalShift],
        "task hub choices should include the restored optional Signal Shift"
    )
}

private func testYouTubeGuardUnlockLeaseExpiresAtFortyFiveMinutes() throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let support = fixture.directory.appendingPathComponent("guard", isDirectory: true)
    let storage = YouTubeGuardStorage(
        stateURL: support.appendingPathComponent("state.json"),
        requestDirectoryURL: support.appendingPathComponent("requests", isDirectory: true),
        responseDirectoryURL: support.appendingPathComponent("responses", isDirectory: true)
    )
    var currentDate = Date(timeIntervalSinceReferenceDate: 50_000)
    let engine = try YouTubeGuardEngine(
        hostsFileURL: fixture.hostsFile,
        storage: storage,
        authorizationValidator: { $0 == "valid-authorization" },
        now: { currentDate }
    )

    _ = try engine.enforce()
    try check(try FocusVaultBlocker(hostsFileURL: fixture.hostsFile).isBlocked(), "guard did not fail closed before a lease")

    let request = YouTubeGuardRequest(
        command: .unlock,
        authorization: "valid-authorization",
        createdAt: currentDate
    )
    let response = try engine.process(request)
    try check(response.succeeded, "valid unlock request failed")
    try check(!(try FocusVaultBlocker(hostsFileURL: fixture.hostsFile).isBlocked()), "valid lease did not open YouTube")
    let state = storage.readState(now: currentDate)
    try checkEqual(state.remainingSeconds(at: currentDate), 2_700, "unlock lease was not exactly 45 minutes")

    let extensionAttempt = try engine.process(
        YouTubeGuardRequest(command: .unlock, authorization: "valid-authorization", createdAt: currentDate)
    )
    try check(!extensionAttempt.succeeded, "an active lease was extended in place")
    try checkEqual(
        storage.readState(now: currentDate).unlockedUntil,
        state.unlockedUntil,
        "rejected unlock changed the fixed lease deadline"
    )

    currentDate = currentDate.addingTimeInterval(2_699)
    _ = try engine.enforce()
    try check(!(try FocusVaultBlocker(hostsFileURL: fixture.hostsFile).isBlocked()), "guard relocked before 45 minutes")

    currentDate = currentDate.addingTimeInterval(2)
    _ = try engine.enforce()
    try check(try FocusVaultBlocker(hostsFileURL: fixture.hostsFile).isBlocked(), "guard did not relock after 45 minutes")
    try checkEqual(storage.readState(now: currentDate).remainingSeconds(at: currentDate), 0, "expired lease retained time")
}

private func testYouTubeGuardRejectsInvalidAuthorization() throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let support = fixture.directory.appendingPathComponent("guard", isDirectory: true)
    let storage = YouTubeGuardStorage(
        stateURL: support.appendingPathComponent("state.json"),
        requestDirectoryURL: support.appendingPathComponent("requests", isDirectory: true),
        responseDirectoryURL: support.appendingPathComponent("responses", isDirectory: true)
    )
    let currentDate = Date(timeIntervalSinceReferenceDate: 60_000)
    let engine = try YouTubeGuardEngine(
        hostsFileURL: fixture.hostsFile,
        storage: storage,
        authorizationValidator: { _ in false },
        now: { currentDate }
    )

    _ = try engine.enforce()
    let request = YouTubeGuardRequest(
        command: .unlock,
        authorization: "forged",
        createdAt: currentDate
    )
    let response = try engine.process(request)
    try check(!response.succeeded, "invalid authorization opened YouTube")
    try check(response.message.contains("not valid"), "invalid authorization returned the wrong failure")
    try check(try FocusVaultBlocker(hostsFileURL: fixture.hostsFile).isBlocked(), "invalid authorization changed the block")
}

private func testYouTubeGuardLockNeedsNoAuthorization() throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let support = fixture.directory.appendingPathComponent("guard", isDirectory: true)
    let storage = YouTubeGuardStorage(
        stateURL: support.appendingPathComponent("state.json"),
        requestDirectoryURL: support.appendingPathComponent("requests", isDirectory: true),
        responseDirectoryURL: support.appendingPathComponent("responses", isDirectory: true)
    )
    let currentDate = Date(timeIntervalSinceReferenceDate: 70_000)
    let engine = try YouTubeGuardEngine(
        hostsFileURL: fixture.hostsFile,
        storage: storage,
        authorizationValidator: { _ in true },
        now: { currentDate }
    )

    _ = try engine.process(
        YouTubeGuardRequest(command: .unlock, authorization: "valid", createdAt: currentDate)
    )
    let lockResponse = try engine.process(
        YouTubeGuardRequest(command: .lock, authorization: nil, createdAt: currentDate)
    )
    try check(lockResponse.succeeded, "password-free lock request failed")
    try check(try FocusVaultBlocker(hostsFileURL: fixture.hostsFile).isBlocked(), "password-free request did not lock YouTube")
    try checkEqual(storage.readState(now: currentDate).unlockedUntil, nil, "manual lock retained an unlock deadline")
}

private func testYouTubeGuardPreservesShortFormScopesAcrossLease() throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let youtube = try FocusVaultBlocker(hostsFileURL: fixture.hostsFile)
    let fullShortForm = try ShortFormBlocker(hostsFileURL: fixture.hostsFile)
    let leaseShortForm = try ShortFormBlocker(
        hostsFileURL: fixture.hostsFile,
        domains: ShortFormPolicy.nonYouTubeHosts
    )
    _ = try youtube.block()
    _ = try fullShortForm.block()

    let support = fixture.directory.appendingPathComponent("guard", isDirectory: true)
    let storage = YouTubeGuardStorage(
        stateURL: support.appendingPathComponent("state.json"),
        requestDirectoryURL: support.appendingPathComponent("requests", isDirectory: true),
        responseDirectoryURL: support.appendingPathComponent("responses", isDirectory: true)
    )
    var currentDate = Date(timeIntervalSinceReferenceDate: 80_000)
    let engine = try YouTubeGuardEngine(
        hostsFileURL: fixture.hostsFile,
        storage: storage,
        authorizationValidator: { _ in true },
        now: { currentDate }
    )

    let response = try engine.process(
        YouTubeGuardRequest(command: .unlock, authorization: "valid", createdAt: currentDate)
    )
    try check(response.succeeded, "short-form-aware unlock failed")
    try check(!(try youtube.isBlocked()), "YouTube marker remained during its lease")
    try check(try leaseShortForm.isBlocked(), "non-YouTube short-form hosts were opened during a YouTube lease")
    try check(!(try fullShortForm.isBlocked()), "YouTube hosts remained in the short-form section during a YouTube lease")
    try checkEqual(storage.readState(now: currentDate).restoreShortForm, true, "short-form restore scope was not persisted")

    currentDate = currentDate.addingTimeInterval(2_701)
    _ = try engine.enforce()
    try check(try youtube.isBlocked(), "YouTube did not relock after the lease")
    try check(try fullShortForm.isBlocked(), "full short-form protection was not restored after the lease")
    try checkEqual(storage.readState(now: currentDate).restoreShortForm, nil, "restored short-form scope was not cleared")
}

private func testYouTubeGuardRollsBackWhenSuccessCannotBeReported() throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let support = fixture.directory.appendingPathComponent("guard", isDirectory: true)
    try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
    let invalidResponses = support.appendingPathComponent("responses")
    try "not a directory".write(to: invalidResponses, atomically: true, encoding: .utf8)
    let storage = YouTubeGuardStorage(
        stateURL: support.appendingPathComponent("state.json"),
        requestDirectoryURL: support.appendingPathComponent("requests", isDirectory: true),
        responseDirectoryURL: invalidResponses
    )
    let currentDate = Date(timeIntervalSinceReferenceDate: 90_000)
    let engine = try YouTubeGuardEngine(
        hostsFileURL: fixture.hostsFile,
        storage: storage,
        authorizationValidator: { _ in true },
        now: { currentDate }
    )

    do {
        _ = try engine.process(
            YouTubeGuardRequest(command: .unlock, authorization: "valid", createdAt: currentDate)
        )
        throw SelfTestFailure(message: "unlock succeeded without a writable response channel")
    } catch is SelfTestFailure {
        throw SelfTestFailure(message: "unlock succeeded without a writable response channel")
    } catch {
        // The response channel is deliberately broken; the lock must still be restored.
    }

    try check(try FocusVaultBlocker(hostsFileURL: fixture.hostsFile).isBlocked(), "failed success response left YouTube open")
    let state = storage.readState(now: currentDate)
    try check(state.locked, "failed success response retained an open state")
    try checkEqual(state.unlockedUntil, nil, "failed success response retained a lease deadline")
}

@main
private struct FocusVaultSelfTest {
    static func main() {
        let tests: [(String, () throws -> Void)] = [
            ("default block contains all domains", testDefaultBlockContainsAllDomains),
            ("short-form policy covers requested platforms", testShortFormPolicyCoversRequestedPlatforms),
            ("short-form blocker covers requested hosts", testShortFormBlockerCoversRequestedHosts),
            ("short-form blocker is independent from YouTube blocker", testShortFormBlockerIsIndependentFromYouTubeBlocker),
            ("default YouTube channel allowlist", testDefaultYouTubeChannelAllowlist),
            ("productivity log same-day aggregation", testProductivityLogAggregatesSameDay),
            ("productivity log day separation", testProductivityLogSeparatesDays),
            ("productivity log non-positive values", testProductivityLogIgnoresNonPositiveMinutes),
            ("productivity log overflow clamp", testProductivityLogClampsOverflow),
            ("productivity store persistence", testProductivityStorePersistsAndReloads),
            ("productivity store missing file", testProductivityStoreMissingFileStartsEmpty),
            ("productivity store legacy migration", testProductivityStoreMigratesLegacyFile),
            ("productivity store corrupt file", testProductivityStoreRejectsCorruptFile),
            ("productivity date key", testProductivityDateKeyUsesCalendarDay),
            ("empty existing file", testEmptyExistingFile),
            ("missing hosts file creation", testMissingHostsFileCreated),
            ("preserve no final newline", testPreservesNoFinalNewline),
            ("preserve final newline", testPreservesExistingFinalNewline),
            ("preserve Unicode comments", testPreservesUnicodeComments),
            ("block idempotency", testBlockIsIdempotent),
            ("unblock idempotency", testUnblockIsIdempotent),
            ("exact content restoration", testUnblockRestoresExactContent),
            ("unblocked status", testStatusUnblocked),
            ("blocked status", testStatusBlocked),
            ("custom domains", testCustomDomains),
            ("domain order and deduplication", testCustomDomainOrderAndDeduplication),
            ("HTTPS normalization", testHTTPSNormalization),
            ("bare path normalization", testBarePathNormalization),
            ("case and dot normalization", testCaseAndDotNormalization),
            ("CRLF block", testCRLFBlockUsesCRLF),
            ("CRLF restoration", testCRLFUnblockPreservesExactContent),
            ("FocusVault marker migration", testFocusVaultBlockMigrates),
            ("FocusVault marker unblock", testFocusVaultUnblock),
            ("Frostwall marker migration", testLegacyBlockMigrates),
            ("Frostwall marker unblock", testLegacyUnblock),
            ("CRLF legacy migration", testCRLFLegacyMigration),
            ("comment marker safety", testMarkerTextInsideCommentIsIgnored),
            ("indented marker safety", testLeadingWhitespaceMarkerIsIgnored),
            ("similar marker safety", testSimilarMarkerIsIgnored),
            ("begin-only rejection", testMalformedBeginOnly),
            ("end-only rejection", testMalformedEndOnly),
            ("reversed marker rejection", testReversedMarkers),
            ("mismatched marker rejection", testMismatchedMarkers),
            ("duplicate block rejection", testDuplicateManagedBlocks),
            ("mixed block rejection", testFocusAndLegacyTogether),
            ("nested marker rejection", testNestedMarkers),
            ("managed content replacement", testExternalContentInsideBlockIsReplaced),
            ("empty domain rejection", testRejectEmptyDomain),
            ("whitespace domain rejection", testRejectWhitespaceDomain),
            ("wildcard rejection", testRejectWildcard),
            ("comment injection rejection", testRejectCommentInjection),
            ("newline injection rejection", testRejectNewlineInjection),
            ("IPv4 rejection", testRejectIPv4Literal),
            ("IPv6 rejection", testRejectIPv6Literal),
            ("empty label rejection", testRejectEmptyLabel),
            ("hyphen label rejection", testRejectHyphenLabel),
            ("long label rejection", testRejectLongLabel),
            ("long domain rejection", testRejectLongDomain),
            ("Unicode hostname rejection", testRejectUnicodeHostname),
            ("localhost acceptance", testAcceptLocalhost),
            ("punycode acceptance", testAcceptPunycode),
            ("HTTPS port acceptance", testAcceptHTTPSPort),
            ("missing parent write error", testMissingParentWriteError),
            ("directory read error", testDirectoryReadError),
            ("permission preservation", testPermissionsPreserved),
            ("large hosts file", testLargeHostsFile),
            ("100 repeated cycles", testRepeatedCycles),
            ("custom block/default unblock", testCustomBlockThenDefaultUnblock),
            ("unmanaged unblock safety", testUnblockWithoutBlockDoesNotChange),
            ("prefix and suffix preservation", testPrefixAndSuffixRemain),
            ("malformed status rejection", testStatusMalformedThrows),
            ("empty custom list rejection", testEmptyCustomDomainListThrows),
            ("sleep calculator bedtimes", testSleepCalculatorBedtimes),
            ("sleep calculator wake times and filtering", testSleepCalculatorWakeTimesAndFiltering),
            ("task clock exact estimate", testTaskClockAcceptsExactEstimate),
            ("task clock invalid estimate", testTaskClockRejectsInvalidEstimate),
            ("task clock pause remainder", testTaskClockPausePreservesRemainder),
            ("task clock resume, completion, and stop", testTaskClockResumesCompletesAndStops),
            ("Signal Shift coordinate transforms", testSignalShiftTransformsCoordinates),
            ("Signal Shift difficulty progression", testSignalShiftDifficultyProgression),
            ("Signal Shift three-round completion", testSignalShiftRequiresThreeCompletedRounds),
            ("Signal Shift practice room", testSignalShiftPracticeRoomCostsNoLives),
            ("Signal Shift three-life lockout", testSignalShiftThreeLivesLockOut),
            ("Grid Shot scoring and relocation", testGridShotScoringAndTargetRelocation),
            ("Grid Shot hard target", testGridShotHardTargetIsThirty),
            ("Typing Sprint Monkeytype completion", testTypingSprintMonkeytypeCompletion),
            ("root-owned administrator unlock policy", testRootOwnedAdminUnlockPolicy),
            ("required unlock challenge rotation", testUnlockChallengeKindsRemainComplete),
            ("YouTube guard 45-minute expiry", testYouTubeGuardUnlockLeaseExpiresAtFortyFiveMinutes),
            ("YouTube guard authorization rejection", testYouTubeGuardRejectsInvalidAuthorization),
            ("YouTube guard password-free lock", testYouTubeGuardLockNeedsNoAuthorization),
            ("YouTube guard short-form scope restoration", testYouTubeGuardPreservesShortFormScopesAcrossLease),
            ("YouTube guard response failure rollback", testYouTubeGuardRollsBackWhenSuccessCannotBeReported)
        ]

        var failures: [(String, String)] = []
        for (index, test) in tests.enumerated() {
            do {
                try test.1()
                print("PASS [\(index + 1)/\(tests.count)]: \(test.0)")
            } catch {
                let message = String(describing: error)
                failures.append((test.0, message))
                print("FAIL [\(index + 1)/\(tests.count)]: \(test.0) — \(message)")
            }
        }

        if failures.isEmpty {
            print("PASS: all \(tests.count) Vaulty edge-case tests completed")
        } else {
            print("FAIL: \(failures.count) of \(tests.count) Vaulty edge-case tests failed")
            for (name, message) in failures {
                print("  - \(name): \(message)")
            }
            Darwin.exit(EXIT_FAILURE)
        }
    }
}
