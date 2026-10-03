import Darwin
import Foundation

/// Refactor regressions: only temporary files and owned throwaway shell children.
/// No real bb/caffeinate command, live listener, or standard preferences are used.
enum LocalToolRefactorSelfTest {
    private struct Failure: Error { let message: String }
    private static func check(_ value: Bool, _ message: String) throws {
        if !value { throw Failure(message: message) }
    }
    private static func rejects(_ action: () throws -> Void) -> Bool {
        do { try action(); return false } catch { return true }
    }
    private static func wait(_ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if condition() { return true }
            _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
        return condition()
    }

    @MainActor
    static func run(in directory: URL) throws {
        let root = directory.appendingPathComponent("local-tool-refactor", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let definition = LocalToolDefinition.defaults()[0]
        for url in ["http://user@localhost:38886", "http://localhost:38886/?instance=other",
                    "http://localhost:38886/other", "https://localhost:38886"] {
            var modified = definition
            modified.links[0].urlString = url
            try check(!BBExternalLifecycle.matches(modified), "non-default bb URL accepted: \(url)")
        }
        var modified = definition
        modified.workingDirectory = root.path
        try check(!BBExternalLifecycle.matches(modified), "custom working directory qualified for default bb stop")
        let recordDirectory = root.appendingPathComponent("bb", isDirectory: true)
        try FileManager.default.createDirectory(at: recordDirectory, withIntermediateDirectories: true)
        let recordFile = recordDirectory.appendingPathComponent("bb-app-runtime.json")
        let record: [String: Any] = ["entryPath": "/fixture/bb.js", "pid": 123,
            "surface": "app", "serverUrl": "http://127.0.0.1:38886", "startedAt": "fixture", "version": "1"]
        let validRecord = try JSONSerialization.data(withJSONObject: record)
        try validRecord.write(to: recordFile)
        try BBExternalLifecycle.validateRuntime(in: recordDirectory)
        try Data(repeating: 32, count: 65_537).write(to: recordFile)
        try check(rejects { try BBExternalLifecycle.validateRuntime(in: recordDirectory) }, "oversized runtime record accepted")
        try FileManager.default.removeItem(at: recordFile)
        let target = root.appendingPathComponent("valid-runtime.json")
        try validRecord.write(to: target)
        try FileManager.default.createSymbolicLink(at: recordFile, withDestinationURL: target)
        try check(rejects { try BBExternalLifecycle.validateRuntime(in: recordDirectory) }, "symlink runtime record accepted")
        try FileManager.default.removeItem(at: recordFile)

        let runs = root.appendingPathComponent("runs", isDirectory: true)
        try FileManager.default.createDirectory(at: runs, withIntermediateDirectories: true)
        let manager = LocalToolsManager(
            catalog: LocalToolCatalog(fileURL: root.appendingPathComponent("tools.json")),
            defaults: [definition], supervisorExecutableURL: nil, runDirectory: runs,
            logDirectory: root.appendingPathComponent("logs"), startsStatusTimer: false,
            opensWhenReady: false, portProbe: { _, done in done([38886: false]) }, openURL: { _ in true })
        let runtime = manager.tools[0]
        let absentPID: pid_t = 2_147_483_647
        try check(kill(absentPID, 0) == -1 && errno == ESRCH, "fixture PID was not absent")
        runtime.supervisorPID = absentPID
        let childMetadata = runs.appendingPathComponent("\(runtime.id.uuidString).json.child-pgid")
        try check(manager.ownedGroupsExited(runtime), "legacy run without child metadata could not verify exit")
        for invalid in ["invalid", "0", "-1", ""] {
            try invalid.write(to: childMetadata, atomically: true, encoding: .utf8)
            try check(!manager.ownedGroupsExited(runtime), "malformed child group permitted ownership clearing")
        }
        manager.refreshStatus(runtime)
        try check(runtime.isOwned && runtime.state == .failed, "status discarded unknown child-group ownership")
        try FileManager.default.removeItem(at: childMetadata)
        manager.refreshStatus(runtime)
        try check(!runtime.isOwned, "verified exit plus closed ports retained ownership")

        // An unverified live PID must never be advertised as Vaulty-owned.
        runtime.supervisorPID = getpid()
        runtime.state = .stopped
        manager.refreshStatus(runtime)
        try check(runtime.state == .failed && runtime.isOwned, "unverified process was advertised as owned/running")
        runtime.supervisorPID = nil // Never signal the deliberately unowned fixture PID.

        var pending: [([Int: Bool]) -> Void] = []
        let delayed = LocalToolsManager(
            catalog: LocalToolCatalog(fileURL: root.appendingPathComponent("delayed-tools.json")),
            defaults: [definition], supervisorExecutableURL: nil, startsStatusTimer: false,
            opensWhenReady: false, portProbe: { _, done in pending.append(done) },
            externalBBStop: { _ in }, openURL: { _ in true })
        let external = delayed.tools[0]
        pending.removeFirst()([38886: true])
        delayed.stop(external)
        try check(wait { !pending.isEmpty }, "external stop did not reach closure verification")
        let stale = pending.removeFirst()
        delayed.beginOperation(external)
        external.restartPending = false
        external.state = .runningExternal
        stale([38886: false])
        try check(external.state == .runningExternal && !external.isOwned, "stale external closure callback changed newer operation")
        print("PASS: local-tool refactor allowlist/runtime identity, malformed child metadata, unverified PID, and stale external callback fixtures")

        let success = try LocalToolCommandRunner.run(executable: "/bin/sh", arguments: ["-c", "printf ready; printf warning >&2"])
        try check(success.status == 0 && success.exitedNormally && !success.timedOut,
                  "bounded command lost successful exit status")
        try check(success.standardOutput == "ready" && success.standardError == "warning", "command streams were not captured separately")
        let pidFile = root.appendingPathComponent("noisy-cli.pid")
        let noisy = try LocalToolCommandRunner.run(executable: "/bin/sh", arguments: ["-c",
            "printf '%s' \"$$\" > \"$1\"; trap '' TERM; while :; do printf stdout-noise; printf stderr-noise >&2; done", "fixture", pidFile.path],
            timeout: 0.15, outputLimit: 1024)
        try check(noisy.timedOut && noisy.status == nil && !noisy.exitedNormally, "noisy CLI evaded timeout")
        try check(noisy.text.utf8.count <= 1024 && noisy.standardOutput.utf8.count <= 1024 && noisy.standardError.utf8.count <= 1024,
                  "CLI output exceeded bounds")
        let pidText = try String(contentsOf: pidFile, encoding: .utf8)
        guard let noisyPID = Int32(pidText) else { throw Failure(message: "fixture CLI PID missing") }
        try check(wait { kill(noisyPID, 0) == -1 && errno == ESRCH }, "SIGTERM-ignoring owned CLI was not reaped")
        print("PASS: separate bounded command streams, noisy-child timeout, and identity-verified child-only cleanup")
    }
}
