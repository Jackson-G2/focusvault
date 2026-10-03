import Foundation
import VaultyCore

enum YouTubeGuardTests {
    static let tests: [SelfTestCase] = [
        ("root-owned administrator unlock policy", testRootOwnedAdminUnlockPolicy),
        ("YouTube guard 45-minute expiry", testYouTubeGuardUnlockLeaseExpiresAtFortyFiveMinutes),
        ("YouTube guard authorization rejection", testYouTubeGuardRejectsInvalidAuthorization),
        ("YouTube guard password-free lock", testYouTubeGuardLockNeedsNoAuthorization),
        ("YouTube guard short-form scope restoration", testYouTubeGuardPreservesShortFormScopesAcrossLease),
        ("YouTube guard response failure rollback", testYouTubeGuardRollsBackWhenSuccessCannotBeReported)
    ]
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
