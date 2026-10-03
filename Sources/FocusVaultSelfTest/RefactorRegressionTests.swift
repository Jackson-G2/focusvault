import Darwin
import Foundation
import VaultyCore

enum RefactorRegressionTests {
    static let tests: [SelfTestCase] = [
        ("independent sections exact byte restoration matrix", exactIndependentRoundTrips),
        ("hosts symlink and dangling symlink safety", hostsSymlinks),
        ("hosts ownership mode and extended attribute preservation", hostsMetadata),
        ("guard replacement failure keeps destination and cleans staging", atomicGuardStorage),
        ("guard request bounded no-follow inode snapshot", requestSnapshot),
        ("guard state failure changes no protected bytes", stateFailure),
        ("expired lease renewal retains short-form restoration", expiredLeaseRenewal),
        ("short-form commented mappings are not coverage", commentedMappings),
        ("Kivlet metadata migration restores exact original bytes", kivletRoundTrip)
    ]

    private static func exactIndependentRoundTrips() throws {
        let originals = ["", "\n", "\r\n", "# e\u{301} ✨", "# é\r", "# notes\r\n127.0.0.1 localhost", "# notes\n127.0.0.1 localhost\n", "# mixed\r\n127.0.0.1 localhost\n"]
        for original in originals {
            for shortFirst in [false, true] {
                for removeShortFirst in [false, true] {
                    try withFixture(initial: original) { hosts in
                        let youtube = try FocusVaultBlocker(hostsFileURL: hosts)
                        let short = try ShortFormBlocker(hostsFileURL: hosts)
                        if shortFirst { _ = try short.block(); _ = try youtube.block() }
                        else { _ = try youtube.block(); _ = try short.block() }
                        let protectedBytes = try Data(contentsOf: hosts)
                        for _ in 0..<3 {
                            try check(!(try youtube.block()), "YouTube enforcement moved a section")
                            try check(!(try short.block()), "short-form enforcement moved a section")
                        }
                        try checkEqual(try Data(contentsOf: hosts), protectedBytes, "enforcement byte drift")
                        if removeShortFirst { _ = try short.unblock(); _ = try youtube.unblock() }
                        else { _ = try youtube.unblock(); _ = try short.unblock() }
                        try checkEqual(try Data(contentsOf: hosts), Data(original.utf8), "independent section round-trip byte drift")
                    }
                }
            }
        }
    }

    private static func hostsSymlinks() throws {
        try withFixture { target in
            let link = target.deletingLastPathComponent().appendingPathComponent("hosts-link")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
            let blocker = try FocusVaultBlocker(hostsFileURL: link)
            _ = try blocker.block(); _ = try blocker.unblock()
            try checkEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link.path), target.path, "hosts link replaced")
            try checkEqual(try read(target), defaultFixtureContents, "symlink target did not restore")
            let missing = target.deletingLastPathComponent().appendingPathComponent("missing")
            let dangling = target.deletingLastPathComponent().appendingPathComponent("dangling")
            try FileManager.default.createSymbolicLink(at: dangling, withDestinationURL: missing)
            try expectFocusVaultError({ _ = try FocusVaultBlocker(hostsFileURL: dangling).block() }, "dangling hosts link")
            try checkEqual(try FileManager.default.destinationOfSymbolicLink(atPath: dangling.path), missing.path, "dangling link replaced")
            try check(!FileManager.default.fileExists(atPath: missing.path), "missing symlink target unexpectedly created")
        }
    }

    private static func hostsMetadata() throws {
        try withFixture { hosts in
            let before = try FileManager.default.attributesOfItem(atPath: hosts.path)
            try check(chmod(hosts.path, 0o640) == 0, "could not set fixture mode")
            let value = Array("preserved".utf8)
            try check(value.withUnsafeBytes { setxattr(hosts.path, "com.vaulty.selftest", $0.baseAddress, $0.count, 0, 0) } == 0, "could not set fixture xattr")
            let blocker = try FocusVaultBlocker(hostsFileURL: hosts)
            _ = try blocker.block(); _ = try blocker.unblock()
            let after = try FileManager.default.attributesOfItem(atPath: hosts.path)
            for key in [FileAttributeKey.ownerAccountID, .groupOwnerAccountID] {
                try checkEqual((after[key] as? NSNumber)?.uint32Value, (before[key] as? NSNumber)?.uint32Value, "hosts owner/group changed")
            }
            try checkEqual((after[.posixPermissions] as? NSNumber)?.intValue, 0o640, "hosts mode changed")
            var bytes = [UInt8](repeating: 0, count: 32)
            let count = bytes.withUnsafeMutableBytes { getxattr(hosts.path, "com.vaulty.selftest", $0.baseAddress, $0.count, 0, 0) }
            try check(count >= 0, "hosts extended attribute was lost")
            try checkEqual(Array(bytes.prefix(Int(count))), value, "hosts extended attribute changed")
        }
    }

    private static func storage(in directory: URL, state: URL? = nil, responses: URL? = nil) -> YouTubeGuardStorage {
        YouTubeGuardStorage(stateURL: state ?? directory.appendingPathComponent("state.json"), requestDirectoryURL: directory.appendingPathComponent("requests"), responseDirectoryURL: responses ?? directory.appendingPathComponent("responses"))
    }

    private static func atomicGuardStorage() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("state.json")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        do { try storage(in: directory).writeState(YouTubeGuardState()); throw SelfTestFailure(message: "directory destination overwritten") }
        catch is SelfTestFailure { throw SelfTestFailure(message: "directory destination overwritten") }
        catch { }
        var isDirectory: ObjCBool = false
        try check(FileManager.default.fileExists(atPath: destination.path, isDirectory: &isDirectory) && isDirectory.boolValue, "failed publication deleted destination")
        try checkEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted(), ["state.json"], "failed publication leaked staging")
        try FileManager.default.removeItem(at: destination)
        let store = storage(in: directory)
        for _ in 0..<3 { try store.writeState(YouTubeGuardState()) }
        try checkEqual((try FileManager.default.attributesOfItem(atPath: destination.path)[.posixPermissions] as? NSNumber)?.intValue, 0o644, "state mode wrong")
        let request = YouTubeGuardRequest(command: .lock)
        let requestURL = try store.writeRequest(request)
        try checkEqual((try FileManager.default.attributesOfItem(atPath: requestURL.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600, "request token file mode wrong")
    }

    private static func requestSnapshot() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = storage(in: directory)
        // Deterministic, exactly representable fractional time: Date() can
        // carry precision which Foundation's JSON date encoding rounds.
        let request = YouTubeGuardRequest(command: .lock, createdAt: Date(timeIntervalSinceReferenceDate: 100_000.125))
        let url = try store.writeRequest(request)
        let snapshot = try store.readRequestWithMetadata(at: url)
        try checkEqual(snapshot.request, request, "request snapshot changed bytes")
        try checkEqual(snapshot.ownerID, UInt32(geteuid()), "snapshot owner not inode owner")
        try checkEqual(snapshot.posixPermissions, 0o600, "snapshot mode not inode mode")
        let symlink = directory.appendingPathComponent("symlink.json")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: url)
        let fifo = directory.appendingPathComponent("fifo.json")
        try check(mkfifo(fifo.path, 0o600) == 0, "could not create request FIFO fixture")
        for bad in [symlink, directory, fifo] {
            do { _ = try store.readRequest(at: bad); throw SelfTestFailure(message: "nonregular request accepted") }
            catch is YouTubeGuardError { }
        }
        do { _ = try store.readRequest(at: url, maximumBytes: 1); throw SelfTestFailure(message: "oversized request accepted") }
        catch YouTubeGuardError.requestTooLarge { }
        do { _ = try store.readRequest(at: url, maximumBytes: -1); throw SelfTestFailure(message: "negative request bound accepted") }
        catch YouTubeGuardError.requestTooLarge { }
    }

    private static func stateFailure() throws {
        try withFixture(initial: "# no newline") { hosts in
            let directory = hosts.deletingLastPathComponent()
            let youtube = try FocusVaultBlocker(hostsFileURL: hosts)
            let short = try ShortFormBlocker(hostsFileURL: hosts)
            _ = try youtube.block(); _ = try short.block()
            let protected = try Data(contentsOf: hosts)
            let invalid = directory.appendingPathComponent("invalid-state")
            try FileManager.default.createDirectory(at: invalid, withIntermediateDirectories: true)
            let engine = try YouTubeGuardEngine(hostsFileURL: hosts, storage: storage(in: directory, state: invalid), authorizationValidator: { _ in true })
            do { _ = try engine.process(YouTubeGuardRequest(command: .unlock, authorization: "mock")); throw SelfTestFailure(message: "unlock succeeded without durable state") }
            catch is SelfTestFailure { throw SelfTestFailure(message: "unlock succeeded without durable state") }
            catch { }
            try checkEqual(try Data(contentsOf: hosts), protected, "failed initial state commit changed protected bytes")
        }
    }

    private static func expiredLeaseRenewal() throws {
        try withFixture { hosts in
            let short = try ShortFormBlocker(hostsFileURL: hosts)
            _ = try short.block()
            var date = Date(timeIntervalSinceReferenceDate: 100_000)
            let store = storage(in: hosts.deletingLastPathComponent())
            let engine = try YouTubeGuardEngine(hostsFileURL: hosts, storage: store, authorizationValidator: { _ in true }, now: { date })
            let response = try engine.process(YouTubeGuardRequest(command: .unlock, authorization: "mock", createdAt: date))
            try check(response.succeeded, "first lease failed")
            date = date.addingTimeInterval(2_701)
            let next = try engine.process(YouTubeGuardRequest(command: .unlock, authorization: "mock", createdAt: date))
            try check(next.succeeded, "expired lease could not restart")
            try checkEqual(store.readState(now: date).restoreShortForm, true, "expired lease lost restoration intent")
            date = date.addingTimeInterval(2_701)
            _ = try engine.enforce()
            try check(try short.isBlocked(), "short-form protection lost after renewed lease")
        }
    }

    private static func commentedMappings() throws {
        try withFixture { hosts in
            let blocker = try ShortFormBlocker(hostsFileURL: hosts)
            _ = try blocker.block()
            var contents = try read(hosts)
            contents = contents.replacingOccurrences(of: "0.0.0.0 tiktok.com", with: "# 0.0.0.0 tiktok.com")
            try write(contents, to: hosts)
            try check(!(try blocker.isBlocked()), "commented host counted as blocked")
            try check(try blocker.missingDomains().contains("tiktok.com"), "commented host not reported missing")
        }
    }

    private static func kivletRoundTrip() throws {
        for ending in ["\n", "\r\n"] {
            let original = "# no newline ✨"
            let managed = [FocusVaultBlocker.kivletBeginMarker, "# Kivlet original prefix ending: none", "0.0.0.0 youtube.com", FocusVaultBlocker.kivletEndMarker, ""].joined(separator: ending)
            try withFixture(initial: original + ending + managed) { hosts in
                let blocker = try FocusVaultBlocker(hostsFileURL: hosts)
                _ = try blocker.block(); _ = try blocker.unblock()
                try checkEqual(try Data(contentsOf: hosts), Data(original.utf8), "legacy prefix restoration metadata lost")
            }
        }
    }
}
