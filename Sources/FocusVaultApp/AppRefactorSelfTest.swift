import Combine
import Foundation
import VaultyCore

/// Refactor regressions exercise real temporary files and deterministic clocks.
/// No root helper, user preferences, researcher network call or live service.
enum AppRefactorSelfTest {
    @MainActor
    static func run(in directory: URL) throws {
        try check(AppCommandDispatcher.parameter(after: "--render-tools-preview", in: ["Vaulty", "--render-tools-preview"]) == nil,
                  "missing preview argument must not launch the GUI")
        try check(AppCommandDispatcher.parameter(after: "--render-tools-preview", in: ["Vaulty", "--render-tools-preview", "--self-test"]) == nil,
                  "another option must not become an output path")
        try check(AppCommandDispatcher.parameter(after: "--render-tools-preview", in: ["Vaulty", "--render-tools-preview", "/tmp/preview.png"]) == "/tmp/preview.png",
                  "valid preview path was not parsed")
        try testUnchangedPublishing(in: directory)
        try testFalseSuccess(in: directory)
        try testCorruptAndBottomEdgeLayouts()
        try testProcessCapture()
    }

    @MainActor
    private static func testUnchangedPublishing(in directory: URL) throws {
        let suite = "VaultyRefactor.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let hosts = directory.appendingPathComponent("refactor-hosts")
        try "127.0.0.1 localhost\n".write(to: hosts, atomically: true, encoding: .utf8)
        _ = try FocusVaultBlocker(hostsFileURL: hosts).block()
        var now = Date(timeIntervalSince1970: 1_000)
        let model = FocusVaultAppModel(
            hostsFileURL: hosts,
            guardInstalled: { true },
            guardStorage: fixtureStorage(in: directory, name: "idle-guard"),
            defaults: defaults,
            startsStatusTimer: false,
            now: { now }
        )
        var changes = 0
        let subscription = model.objectWillChange.sink { changes += 1 }
        defer { subscription.cancel() }
        for _ in 0..<1_000 { model.refreshGuardStatus() }
        try check(changes == 0, "idle guard polling emitted \(changes) redundant UI changes")
        model.startFocusSession(minutes: 1) { _ in }
        changes = 0
        for _ in 0..<100 { model.tickSession() }
        try check(changes == 0, "unchanged task clock emitted redundant UI changes")
        now = now.addingTimeInterval(10)
        model.tickSession()
        try check(model.remainingSessionSeconds == 50, "task clock did not follow injected time")
        model.pauseFocusSession()
        now = now.addingTimeInterval(600)
        model.tickSession()
        try check(model.remainingSessionSeconds == 50, "paused task clock consumed time")
        model.resumeFocusSession()
        now = now.addingTimeInterval(51)
        model.tickSession()
        try check(model.sessionPhase == .completed && model.isSystemBlocked,
                  "task completion did not preserve protection")
        print("PASS: 1,000 unchanged guard polls and 100 unchanged task ticks emit zero UI notifications; deterministic pause/resume/completion")
    }

    @MainActor
    private static func testFalseSuccess(in directory: URL) throws {
        let hosts = directory.appendingPathComponent("false-success-hosts")
        try "127.0.0.1 localhost\n".write(to: hosts, atomically: true, encoding: .utf8)
        let suite = "VaultyFalseSuccess.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = FocusVaultAppModel(
            hostsFileURL: hosts,
            privilegedAction: { _, completion in completion(.success("")) },
            guardRequest: { request, completion in
                completion(.success(YouTubeGuardResponse(requestID: request.id, succeeded: true,
                                                        message: "false fixture", completedAt: Date())))
            },
            guardInstalled: { true },
            guardStorage: fixtureStorage(in: directory, name: "false-guard"),
            defaults: defaults,
            startsStatusTimer: false
        )
        var outcome: Result<Void, Error>?
        model.startFocusSession(minutes: 1) { outcome = $0 }
        guard case .failure = outcome else { throw Failure.failed("false lock success started an unprotected clock") }
        try check(model.sessionPhase == .ready && model.lastError != nil, "false lock was not surfaced")
        // A forged success which leaves only empty markers is not protection.
        try ("127.0.0.1 localhost\n" + FocusVaultBlocker.beginMarker + "\n" + FocusVaultBlocker.endMarker + "\n")
            .write(to: hosts, atomically: true, encoding: .utf8)
        model.refresh()
        try check(!model.isSystemBlocked, "empty YouTube markers were presented as protection")
        outcome = nil
        model.startFocusSession(minutes: 1) { outcome = $0 }
        guard case .failure = outcome else { throw Failure.failed("empty marker false success started an unprotected clock") }
        model.clearError()
        model.toggleShortFormVault()
        try check(!model.isShortFormBlocked && model.lastError != nil, "false short-form success was accepted")
        let notInstalled = FocusVaultAppModel(
            hostsFileURL: hosts,
            privilegedAction: { _, completion in completion(.success("")) },
            guardInstalled: { false },
            guardStorage: fixtureStorage(in: directory, name: "missing-guard"),
            defaults: defaults,
            startsStatusTimer: false
        )
        notInstalled.toggleFullVault()
        try check(!notInstalled.isGuardInstalled && notInstalled.lastError != nil && !notInstalled.isBusy,
                  "false installation success was accepted")
        print("PASS: false-success lock, short-form mutation and guard installation cannot report success")
    }

    @MainActor
    private static func testCorruptAndBottomEdgeLayouts() throws {
        let suite = "VaultyLayoutExtremes.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        struct LayoutFixture: Encodable {
            let version = 3
            let placements: [DashboardWidgetPlacement]
        }
        let invalid = DashboardWidgetKind.allCases.map {
            DashboardWidgetPlacement(kind: $0, column: Int.max, row: Int.max, width: Int.max, height: Int.max)
        }
        defaults.set(try JSONEncoder().encode(LayoutFixture(placements: invalid)), forKey: "extremes")
        let layout = DashboardLayoutModel(defaults: defaults, key: "extremes", legacyKey: "unused")
        try validate(layout.placements)
        for kind in DashboardWidgetKind.allCases {
            layout.move(kind, toColumn: 0, row: 39)
            layout.resize(kind, width: 4, height: 4)
            try validate(layout.placements)
        }
        layout.nudge(.intention, columns: Int.max, rows: Int.max)
        layout.nudge(.intention, columns: Int.min, rows: Int.min)
        try validate(layout.placements)
        var changes = 0
        let subscription = layout.objectWillChange.sink { changes += 1 }
        defer { subscription.cancel() }
        let position = layout.placement(for: .intention)
        let saved = defaults.data(forKey: "extremes")
        for _ in 0..<1_000 {
            layout.move(.intention, toColumn: position.column, row: position.row)
            layout.resize(.intention, width: position.width, height: position.height)
        }
        try check(changes == 0 && saved == defaults.data(forKey: "extremes"),
                  "identical drag/resize requests published or rewrote preferences")
        print("PASS: Int.min/max persisted layouts and nudges, bottom-edge collisions, and 2,000 no-op drag/resize calls")
    }

    private static func validate(_ placements: [DashboardWidgetPlacement]) throws {
        try check(placements.count == DashboardWidgetKind.allCases.count, "layout lost a supported widget")
        for placement in placements {
            try check(placement.column >= 0 && placement.maximumColumn <= 4 && placement.row >= 0 && placement.maximumRow <= 40,
                      "layout exceeded canvas bounds")
        }
        for index in placements.indices {
            for other in placements.indices where other > index {
                try check(!placements[index].intersects(placements[other]), "bottom-edge layout still overlapped")
            }
        }
    }

    private static func testProcessCapture() throws {
        func process() -> Process {
            let child = Process()
            child.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            child.arguments = ["-c", "import os; os.write(1,b's'*262144); os.write(2,b'e'*262144)"]
            return child
        }
        let captured = try ProcessOutputCapture.run(process())
        try check(captured.exitStatus == 0 && captured.stdout.count == 262_144 && captured.stderr.count == 262_144,
                  "simultaneous large pipe capture lost output")
        do {
            _ = try ProcessOutputCapture.run(process(), limit: 4_096)
            throw Failure.failed("oversized subprocess output was not rejected")
        } catch ProcessOutputCaptureError.outputTooLarge {
            // Both streams still drained, so rejection cannot deadlock the child.
        }
        print("PASS: stdout/stderr larger than pipe capacity complete without deadlock; bounded-output rejection drains safely")
    }

    private static func fixtureStorage(in directory: URL, name: String) -> YouTubeGuardStorage {
        let root = directory.appendingPathComponent(name)
        return YouTubeGuardStorage(stateURL: root.appendingPathComponent("state.json"),
                                   requestDirectoryURL: root.appendingPathComponent("requests"),
                                   responseDirectoryURL: root.appendingPathComponent("responses"))
    }

    private static func check(_ condition: Bool, _ message: String) throws {
        if !condition { throw Failure.failed(message) }
    }

    private enum Failure: Error {
        case failed(String)
    }
}
