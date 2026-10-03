import Darwin
import Foundation
import VaultyCore

extension VaultyAppInteractionSelfTest {
    @MainActor
    static func testLocalToolsAsyncRaces(in directory: URL) throws {
        let port = try reserveLocalPort()
        let root = directory.appendingPathComponent("async-races", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var pending: [([Int: Bool]) -> Void] = []
        let definition = LocalToolDefinition(
            name: "Delayed fixture", detail: "Cancellation test", workingDirectory: root.path,
            executablePath: "/usr/bin/python3",
            arguments: ["-c", "import time; time.sleep(60)"],
            links: [LocalToolLink(name: "Fixture", urlString: "http://127.0.0.1:\(port)")],
            expectedPorts: [port])
        let manager = LocalToolsManager(
            catalog: LocalToolCatalog(fileURL: root.appendingPathComponent("tools.json")),
            defaults: [definition], supervisorExecutableURL: Bundle.main.executableURL,
            runDirectory: root.appendingPathComponent("runs"), logDirectory: root.appendingPathComponent("logs"),
            startsStatusTimer: false, opensWhenReady: false,
            portProbe: { _, callback in pending.append(callback) }, openURL: { _ in true })
        let runtime = manager.tools[0]
        defer {
            if runtime.isOwned {
                manager.stop(runtime)
                _ = waitUntil(timeout: 12, condition: {
                    while !pending.isEmpty { pending.removeFirst()([port: false]) }
                    return runtime.state == .stopped
                })
            }
        }
        let initialStatus = pending.removeFirst()
        manager.startOrOpen(runtime)
        let firstStart = pending.removeFirst()
        initialStatus([port: true])
        try checkApp(runtime.state == .checking, "late status callback replaced Checking")
        manager.cancel(runtime)
        firstStart([port: false])
        try checkApp(runtime.state == .stopped && runtime.ownedPID == nil, "cancelled port probe launched a process")
        try checkApp(!FileManager.default.fileExists(atPath: root.appendingPathComponent("runs/\(runtime.id.uuidString).state.json").path),
                     "Cancel before launch wrote an ownership record")
        print("PASS: cancellation before port probe prevents launch; late status cannot override Checking")

        manager.refreshStatuses()
        let lateStatus = pending.removeFirst()
        manager.startOrOpen(runtime)
        pending.removeFirst()([port: false])
        try checkApp(runtime.state == .starting && runtime.ownedPID != nil, "startup fixture did not launch")
        let staleReadiness = pending.removeFirst()
        lateStatus([port: true])
        try checkApp(runtime.state == .starting, "late status callback replaced Starting")
        manager.cancel(runtime)
        staleReadiness([port: true])
        lateStatus([port: true])
        try checkApp(runtime.state == .stopping, "stale readiness/status overrode cancellation")
        guard waitUntil(timeout: 12, condition: {
            while !pending.isEmpty { pending.removeFirst()([port: false]) }
            return runtime.state == .stopped
        }) else { throw InteractionTestError.failed("Cancel during startup did not verify supervisor/group exit") }
        try checkApp(runtime.ownedPID == nil, "startup cancellation retained ownership after verified exit")
        print("PASS: cancellation during startup drains the owned process; stale readiness/status cannot override Stopping")
    }

}
