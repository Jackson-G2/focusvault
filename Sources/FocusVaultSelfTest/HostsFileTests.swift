import Foundation
import VaultyCore

enum HostsFileTests {
    static let tests: [SelfTestCase] = [
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
        ("CRLF block", testCRLFBlockUsesCRLF),
        ("CRLF restoration", testCRLFUnblockPreservesExactContent),
        ("missing parent write error", testMissingParentWriteError),
        ("directory read error", testDirectoryReadError),
        ("permission preservation", testPermissionsPreserved),
        ("large hosts file", testLargeHostsFile),
        ("100 repeated cycles", testRepeatedCycles),
        ("custom block/default unblock", testCustomBlockThenDefaultUnblock),
        ("unmanaged unblock safety", testUnblockWithoutBlockDoesNotChange)
    ]
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
