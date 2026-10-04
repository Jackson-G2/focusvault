import Darwin
import Foundation
import VaultyCore

/// A dependency-free interaction smoke test for the native dashboard. It
/// exercises the same model methods wired to the vault and task-clock buttons
/// without touching the real `/etc/hosts` file or prompting for admin access.
enum VaultyAppInteractionSelfTest {
    @MainActor
    static func run() -> Int32 {
        do {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("vaulty-app-interaction-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            defer { try? FileManager.default.removeItem(at: directory) }

            let suite = "VaultyInteraction.\(UUID().uuidString)"
            guard let defaults = UserDefaults(suiteName: suite) else {
                throw InteractionTestError.failed("could not create isolated model preferences")
            }
            defer { defaults.removePersistentDomain(forName: suite) }

            let hostsFile = directory.appendingPathComponent("hosts")
            try "# app smoke test\n127.0.0.1 localhost\n".write(
                to: hostsFile,
                atomically: true,
                encoding: .utf8
            )

            var privilegedActionCount = 0
            let runner: VaultyPrivilegedActionRunner = { arguments, completion in
                privilegedActionCount += 1
                do {
                    switch arguments.first {
                    case "block":
                        let blocker = try FocusVaultBlocker(hostsFileURL: hostsFile)
                        _ = try blocker.block()
                    case "unblock":
                        let blocker = try FocusVaultBlocker(hostsFileURL: hostsFile)
                        _ = try blocker.unblock()
                    case "short-form-block":
                        let blocker = try ShortFormBlocker(hostsFileURL: hostsFile)
                        _ = try blocker.block()
                    case "short-form-unblock":
                        let blocker = try ShortFormBlocker(hostsFileURL: hostsFile)
                        _ = try blocker.unblock()
                    default:
                        break
                    }
                    completion(.success(""))
                } catch {
                    completion(.failure(error))
                }
            }

            let guardSupport = directory.appendingPathComponent("guard", isDirectory: true)
            let guardStorage = YouTubeGuardStorage(
                stateURL: guardSupport.appendingPathComponent("state.json"),
                requestDirectoryURL: guardSupport.appendingPathComponent("requests", isDirectory: true),
                responseDirectoryURL: guardSupport.appendingPathComponent("responses", isDirectory: true)
            )
            var simulateFalseGuardSuccess = false
            var guardRequestCount = 0
            let guardRunner: VaultyGuardRequestRunner = { request, completion in
                guardRequestCount += 1
                do {
                    if request.command == .unlock, simulateFalseGuardSuccess {
                        completion(.success(
                            YouTubeGuardResponse(
                                requestID: request.id,
                                succeeded: true,
                                message: "false success fixture",
                                completedAt: Date()
                            )
                        ))
                        return
                    }
                    let blocker = try FocusVaultBlocker(hostsFileURL: hostsFile)
                    var state = guardStorage.readState()
                    switch request.command {
                    case .lock:
                        _ = try blocker.block()
                        state.locked = true
                        state.unlockedUntil = nil
                    case .unlock:
                        _ = try blocker.unblock()
                        state.locked = false
                        state.unlockedUntil = Date().addingTimeInterval(YouTubeGuardPaths.sessionDuration)
                    }
                    state.lastRequestID = request.id
                    state.updatedAt = Date()
                    try guardStorage.writeState(state)
                    completion(.success(
                        YouTubeGuardResponse(
                            requestID: request.id,
                            succeeded: true,
                            message: "test",
                            completedAt: Date()
                        )
                    ))
                } catch {
                    completion(.failure(error))
                }
            }

            var adminUnlockCount = 0
            let adminUnlock: VaultyAdminUnlockRunner = { completion in
                adminUnlockCount += 1
                do {
                    if simulateFalseGuardSuccess {
                        completion(.success(()))
                        return
                    }
                    let blocker = try FocusVaultBlocker(hostsFileURL: hostsFile)
                    _ = try blocker.unblock()
                    var state = guardStorage.readState()
                    state.locked = false
                    state.unlockedUntil = Date().addingTimeInterval(YouTubeGuardPaths.sessionDuration)
                    state.updatedAt = Date()
                    try guardStorage.writeState(state)
                    completion(.success(()))
                } catch {
                    completion(.failure(error))
                }
            }

            let model = FocusVaultAppModel(
                hostsFileURL: hostsFile,
                privilegedAction: runner,
                guardRequest: guardRunner,
                guardInstalled: { true },
                adminUnlock: adminUnlock,
                guardStorage: guardStorage,
                defaults: defaults,
                startsStatusTimer: false
            )
            guard !model.isSystemBlocked else {
                throw InteractionTestError.failed("fixture started blocked")
            }

            model.toggleFullVault()
            guard model.isSystemBlocked,
                  !model.isShortFormBlocked,
                  privilegedActionCount == 0,
                  !model.isBusy else {
                throw InteractionTestError.failed("YouTube lock prompted for privileged authorization after guard setup")
            }

            model.toggleFullVault()
            guard model.unlockChallengeRequest != nil,
                  model.selectedUnlockChallengeKind == nil,
                  model.isSystemBlocked,
                  !model.isBusy else {
                throw InteractionTestError.failed("YouTube unlock did not present the task hub")
            }
            let requestsBeforeTaskChoice = adminUnlockCount
            model.completeUnlockChallenge()
            guard adminUnlockCount == requestsBeforeTaskChoice,
                  model.unlockSubmissionError != nil,
                  model.unlockChallengeRequest != nil else {
                throw InteractionTestError.failed("unlock was submitted before a task was chosen and confirmed")
            }
            model.chooseUnlockChallenge(.signalShift)
            guard model.selectedUnlockChallengeKind == .signalShift else {
                throw InteractionTestError.failed("task hub did not restore optional Signal Shift")
            }
            model.chooseUnlockChallenge(.typingSprint)
            guard model.selectedUnlockChallengeKind == .typingSprint else {
                throw InteractionTestError.failed("task hub did not select Typing Sprint")
            }
            model.returnToUnlockTaskHub()
            guard model.selectedUnlockChallengeKind == nil, model.unlockChallengeRequest != nil else {
                throw InteractionTestError.failed("task hub could not be reopened")
            }
            model.chooseUnlockChallenge(.gridShot)
            guard model.selectedUnlockChallengeKind == .gridShot else {
                throw InteractionTestError.failed("task hub did not select Grid Shot")
            }
            model.completeUnlockChallenge()
            guard !model.isSystemBlocked,
                  !model.isShortFormBlocked,
                  model.unlockChallengeRequest == nil,
                  model.selectedUnlockChallengeKind == nil,
                  model.unlockSubmissionError == nil,
                  model.youtubeUnlockRemainingSeconds > 0,
                  !model.isBusy else {
                throw InteractionTestError.failed("explicit game confirmation did not open the verified 45-minute lease")
            }

            model.toggleFullVault()
            guard model.isSystemBlocked,
                  model.youtubeUnlockRemainingSeconds == 0,
                  !model.isBusy else {
                throw InteractionTestError.failed("password-free early lock did not cancel the lease")
            }

            simulateFalseGuardSuccess = true
            model.toggleFullVault()
            model.chooseUnlockChallenge(.typingSprint)
            model.completeUnlockChallenge()
            guard model.isSystemBlocked,
                  model.unlockChallengeRequest != nil,
                  model.selectedUnlockChallengeKind == .typingSprint,
                  model.unlockSubmissionError != nil,
                  !model.isBusy else {
                throw InteractionTestError.failed("false guard success closed the sheet without applying an unlock")
            }
            model.cancelUnlockChallenge()
            simulateFalseGuardSuccess = false

            model.toggleShortFormVault()
            guard model.isShortFormBlocked, model.isSystemBlocked, !model.isBusy else {
                throw InteractionTestError.failed("short-form blocker toggle did not finish")
            }

            model.toggleShortFormVault()
            guard !model.isShortFormBlocked, model.isSystemBlocked, !model.isBusy else {
                throw InteractionTestError.failed("short-form blocker untoggle did not finish")
            }

            var startResult: Result<Void, Error>?
            model.startFocusSession(minutes: 1) { result in
                startResult = result
            }
            if case let .failure(error) = startResult {
                throw InteractionTestError.failed("start task action failed: \(error.localizedDescription)")
            }
            guard startResult != nil, model.sessionPhase == .active else {
                throw InteractionTestError.failed("start task action did not activate the clock")
            }

            model.pauseFocusSession()
            guard model.sessionPhase == .paused else {
                throw InteractionTestError.failed("pause task action did not pause the clock")
            }
            model.resumeFocusSession()
            guard model.sessionPhase == .active else {
                throw InteractionTestError.failed("resume task action did not resume the clock")
            }
            model.endFocusSession()
            guard model.sessionPhase == .ready, model.isSystemBlocked, !model.isShortFormBlocked else {
                throw InteractionTestError.failed("end task action did not reset the clock")
            }

            try AppRefactorSelfTest.run(in: directory)
            try VideoResearchSelfTest.run(in: directory)
            try ProcessTaskSelfTest.run()
            try testDashboardWidgetPersistence()
            try testLocalToolsLifecycle(in: directory)
            try LocalToolsExternalSelfTest.run(in: directory)
            try testCaffeinateLifecycle()

            print("PASS: verified explicit YouTube unlock, selectable task hub, free-position/resizable dashboard persistence, task clock actions, and configurable local-tool lifecycle all changed verified state")
            return 0
        } catch {
            fputs("FAIL: app interaction smoke test — \(error)\n", stderr)
            return 1
        }
    }

    static func checkApp(_ condition: Bool, _ message: String) throws {
        guard condition else { throw InteractionTestError.failed(message) }
    }

    @MainActor
    static func waitUntil(timeout: TimeInterval, condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        return condition()
    }

    static func reserveLocalPort() throws -> Int {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw InteractionTestError.failed("could not create a fixture socket")
        }
        defer { close(descriptor) }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else {
            throw InteractionTestError.failed("could not reserve a fixture port")
        }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let read = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(descriptor, $0, &length)
            }
        }
        guard read == 0 else {
            throw InteractionTestError.failed("could not read the fixture port")
        }
        return Int(UInt16(bigEndian: address.sin_port))
    }
}

enum InteractionTestError: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case let .failed(message):
            return message
        }
    }
}
