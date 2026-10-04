import Foundation
import VaultyCore

enum ManagedMarkerTests {
    static let tests: [SelfTestCase] = [
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
        ("prefix and suffix preservation", testPrefixAndSuffixRemain),
        ("malformed status rejection", testStatusMalformedThrows)
    ]
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
