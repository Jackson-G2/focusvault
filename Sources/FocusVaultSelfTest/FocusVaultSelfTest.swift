import Darwin
import Foundation
import FocusVaultCore

private struct SelfTestFailure: Error, CustomStringConvertible {
    let message: String

    var description: String { message }
}

private struct Fixture {
    let directory: URL
    let hostsFile: URL
}

private let defaultFixtureContents = "# existing entry\n127.0.0.1 localhost\n"

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
        throw SelfTestFailure(message: "expected FocusVaultError: \(message)")
    } catch let error as FocusVaultError {
        if let predicate, !predicate(error) {
            throw SelfTestFailure(message: "wrong FocusVaultError for \(message): \(error)")
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
    try withFixture { hostsFile in
        let blocker = try FocusVaultBlocker(hostsFileURL: hostsFile)
        let changed = try blocker.block()
        try check(changed, "first block should change the hosts file")
        let contents = try read(hostsFile)
        try check(contents.contains(FocusVaultBlocker.beginMarker), "FocusVault begin marker is missing")
        try check(contents.contains(FocusVaultBlocker.endMarker), "FocusVault end marker is missing")
        try check(contents.contains("Vault in and get work done"), "focus tagline is missing from the managed section")
        for domain in FocusVaultBlocker.defaultDomains {
            try check(contents.contains("0.0.0.0 \(domain)"), "missing default domain: \(domain)")
        }
    }
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
    let original = "# Jackson’s focus notes ✨\n127.0.0.1 localhost\n"
    try withFixture(initial: original) { hostsFile in
        let blocker = try FocusVaultBlocker(hostsFileURL: hostsFile)
        _ = try blocker.block()
        try check((try read(hostsFile)).contains("Jackson’s focus notes ✨"), "Unicode comments were lost")
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
        try check(contents.contains("# BEGIN FOCUSVAULT MANAGED BLOCK\r\n"), "CRLF marker line was not preserved")
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

@main
private struct FocusVaultSelfTest {
    static func main() {
        let tests: [(String, () throws -> Void)] = [
            ("default block contains all domains", testDefaultBlockContainsAllDomains),
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
            ("legacy migration", testLegacyBlockMigrates),
            ("legacy unblock", testLegacyUnblock),
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
            ("empty custom list rejection", testEmptyCustomDomainListThrows)
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
            print("PASS: all \(tests.count) FocusVault edge-case tests completed")
        } else {
            print("FAIL: \(failures.count) of \(tests.count) FocusVault edge-case tests failed")
            for (name, message) in failures {
                print("  - \(name): \(message)")
            }
            Darwin.exit(EXIT_FAILURE)
        }
    }
}
