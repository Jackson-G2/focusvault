import Foundation
import FrostwallCore

private struct TestFailure: Error, CustomStringConvertible {
    let message: String

    var description: String { message }
}

private func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else {
        throw TestFailure(message: message)
    }
}

private func checkEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) throws {
    guard actual == expected else {
        throw TestFailure(message: "\(message)\nexpected: \(expected)\nactual: \(actual)")
    }
}

private func makeFixture() throws -> (directory: URL, hostsFile: URL) {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("frostwall-self-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
    )
    let hostsFile = directory.appendingPathComponent("hosts")
    try "# existing entry\n127.0.0.1 localhost\n".write(
        to: hostsFile,
        atomically: true,
        encoding: .utf8
    )
    return (directory, hostsFile)
}

private func read(_ url: URL) throws -> String {
    try String(contentsOf: url, encoding: .utf8)
}

private func testBlockPreservesEntries() throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let blocker = try HostBlocker(hostsFileURL: fixture.hostsFile)

    let firstBlockChanged = try blocker.block()
    try check(firstBlockChanged, "first block should change the hosts file")
    let contents = try read(fixture.hostsFile)
    try check(contents.hasPrefix("# existing entry\n127.0.0.1 localhost\n"), "existing hosts content was not preserved")
    try check(contents.contains(HostBlocker.beginMarker), "begin marker is missing")
    try check(contents.contains(HostBlocker.endMarker), "end marker is missing")
    for domain in HostBlocker.defaultDomains {
        try check(contents.contains("0.0.0.0 \(domain)"), "missing blocked domain: \(domain)")
    }
}

private func testBlockIsIdempotent() throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let blocker = try HostBlocker(hostsFileURL: fixture.hostsFile)

    _ = try blocker.block()
    let first = try read(fixture.hostsFile)
    let secondBlockChanged = try blocker.block()
    try check(!secondBlockChanged, "second block should be idempotent")
    let second = try read(fixture.hostsFile)
    try checkEqual(first, second, "idempotent block changed the file")
    try checkEqual(
        second.components(separatedBy: HostBlocker.beginMarker).count,
        2,
        "more than one managed block was written"
    )
}

private func testUnblockPreservesUnrelatedContent() throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let blocker = try HostBlocker(hostsFileURL: fixture.hostsFile)
    _ = try blocker.block()

    let firstUnblockChanged = try blocker.unblock()
    try check(firstUnblockChanged, "unblock should remove the managed section")
    try checkEqual(
        try read(fixture.hostsFile),
        "# existing entry\n127.0.0.1 localhost\n",
        "unblock did not restore unrelated content exactly"
    )
    let secondUnblockChanged = try blocker.unblock()
    try check(!secondUnblockChanged, "second unblock should be idempotent")
}

private func testCustomDomains() throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let blocker = try HostBlocker(
        hostsFileURL: fixture.hostsFile,
        domains: ["HTTPS://Example.COM/path", "example.com", ".EXAMPLE.org."]
    )

    try checkEqual(blocker.domains, ["example.com", "example.org"], "domain normalization failed")
    _ = try blocker.block()
    let contents = try read(fixture.hostsFile)
    try check(contents.contains("0.0.0.0 example.com"), "normalized example.com is missing")
    try check(contents.contains("0.0.0.0 example.org"), "normalized example.org is missing")
}

private func testMalformedSectionIsRejected() throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    try "# BEGIN FROSTWALL MANAGED BLOCK\n0.0.0.0 youtube.com\n".write(
        to: fixture.hostsFile,
        atomically: true,
        encoding: .utf8
    )
    let blocker = try HostBlocker(hostsFileURL: fixture.hostsFile)

    do {
        _ = try blocker.block()
        throw TestFailure(message: "malformed managed section was accepted")
    } catch let error as HostBlockerError {
        try checkEqual(
            error,
            .malformedManagedBlock(path: fixture.hostsFile.path),
            "wrong error for malformed managed section"
        )
    }
}

@main
private struct FrostwallSelfTest {
    static func main() {
        let tests: [(String, () throws -> Void)] = [
            ("block preserves entries", testBlockPreservesEntries),
            ("block is idempotent", testBlockIsIdempotent),
            ("unblock preserves unrelated content", testUnblockPreservesUnrelatedContent),
            ("custom domains", testCustomDomains),
            ("malformed sections are rejected", testMalformedSectionIsRejected)
        ]

        do {
            for (name, test) in tests {
                try test()
                print("PASS: \(name)")
            }
            print("PASS: \(tests.count) Frostwall self-tests")
        } catch {
            FileHandle.standardError.write(Data("FAIL: \(error)\n".utf8))
            Foundation.exit(1)
        }
    }
}
