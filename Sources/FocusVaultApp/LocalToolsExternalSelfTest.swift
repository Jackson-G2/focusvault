import Foundation

/// No real bb command, process, or listener is touched by these tests.
enum LocalToolsExternalSelfTest {
    private struct Failure: Error { let message: String }
    private final class StopSpy: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        var calls: Int { lock.lock(); defer { lock.unlock() }; return count }
        func stopped() { lock.lock(); defer { lock.unlock() }; count += 1 }
    }

    @MainActor
    static func run(in directory: URL) throws {
        func check(_ valid: Bool, _ message: String) throws {
            if !valid { throw Failure(message: message) }
        }
        func wait(_ condition: () -> Bool) -> Bool {
            let deadline = Date().addingTimeInterval(3)
            while Date() < deadline {
                if condition() { return true }
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
            }
            return condition()
        }
        let definition = LocalToolDefinition.defaults()[0]
        try check(BBExternalLifecycle.matches(definition), "default bb did not qualify")
        var other = definition
        other.id = UUID()
        try check(!BBExternalLifecycle.matches(other), "arbitrary tool qualified for external stop")
        other = definition
        other.arguments.append("--data-dir=/tmp/another-bb")
        try check(!BBExternalLifecycle.matches(other), "custom instance qualified for default stop")
        other = definition
        other.links[0].urlString = "http://example.com:38886"
        try check(!BBExternalLifecycle.matches(other), "remote bb qualified for local stop")
        other = definition
        other.expectedPorts.append(38887)
        try check(!BBExternalLifecycle.matches(other), "different port definition qualified")

        var listenerOpen = true
        let spy = StopSpy()
        let manager = LocalToolsManager(
            catalog: LocalToolCatalog(fileURL: directory.appendingPathComponent("external-bb-test/tools.json")),
            defaults: [definition], supervisorExecutableURL: nil,
            startsStatusTimer: false, opensWhenReady: false,
            portProbe: { _, completion in completion([38886: listenerOpen]) },
            externalBBStop: { _ in spy.stopped() }, openURL: { _ in true })
        let runtime = manager.tools[0]
        try check(runtime.state == .runningExternal, "fixture was not external")
        manager.stop(runtime)
        try check(wait { spy.calls == 1 }, "official stop adapter was not called")
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.08))
        try check(runtime.state == .stopping, "external stop succeeded before port closed")
        listenerOpen = false
        try check(wait { runtime.state == .stopped }, "external stop did not verify port closure")

        listenerOpen = true
        manager.refreshStatus(runtime)
        manager.restart(runtime)
        try check(wait { spy.calls == 2 }, "external restart did not invoke stop adapter")
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.08))
        try check(runtime.state == .stopping, "external restart relaunched while port remained open")
        listenerOpen = false
        // Nil supervisor intentionally prevents any real bb launch. The error
        // proves Restart reached launch only after mocked port closure.
        try check(wait { runtime.state == .failed }, "restart did not reach its guarded launch")
        try check(runtime.errorText == LocalToolError.supervisorUnavailable.localizedDescription,
                  "external restart failed for an unexpected reason")

        let failedManager = LocalToolsManager(
            catalog: LocalToolCatalog(fileURL: directory.appendingPathComponent("external-bb-failure/tools.json")),
            defaults: [definition], supervisorExecutableURL: nil,
            startsStatusTimer: false, opensWhenReady: false,
            portProbe: { _, completion in completion([38886: true]) },
            externalBBStop: { _ in throw BBExternalLifecycle.Failure.cliUnavailable },
            openURL: { _ in true })
        let failed = failedManager.tools[0]
        failedManager.restart(failed)
        try check(wait { failed.state == .runningExternal && failed.errorText != nil },
                  "failed stop lost external recovery state")
        try check(failed.ownedPID == nil, "external stop claimed ownership")
        print("PASS: external bb allowlist, verified port-closure ordering, restart handoff, and stop failure recovery (mock CLI; no live bb touched)")
        try LocalToolRefactorSelfTest.run(in: directory)
    }
}
