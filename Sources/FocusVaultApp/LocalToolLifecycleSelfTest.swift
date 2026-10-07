import Darwin
import Foundation
import VaultyCore

extension VaultyAppInteractionSelfTest {
    @MainActor
    static func runLiveToolsSmoke(workspaceDirectory: String) -> Int32 {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("vaulty-live-tools-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }

            let workspaceRoot = URL(
                fileURLWithPath: (workspaceDirectory as NSString).expandingTildeInPath,
                isDirectory: true
            )
            guard let workspace = LocalToolDefinition.defaults(workspaceRoot: workspaceRoot)
                .first(where: { $0.name == "Workspace hub" }) else {
                throw InteractionTestError.failed("workspace default tool is missing")
            }
            let initialPorts = Dictionary(
                uniqueKeysWithValues: workspace.expectedPorts.map { ($0, LocalToolsManager.portIsOpen($0)) }
            )
            let manager = LocalToolsManager(
                catalog: LocalToolCatalog(fileURL: directory.appendingPathComponent("tools.json")),
                defaults: [workspace],
                supervisorExecutableURL: Bundle.main.executableURL,
                runDirectory: directory.appendingPathComponent("runs", isDirectory: true),
                logDirectory: directory.appendingPathComponent("logs", isDirectory: true),
                startsStatusTimer: false,
                opensWhenReady: false,
                openURL: { _ in true }
            )
            guard let runtime = manager.tools.first else {
                throw InteractionTestError.failed("workspace runtime was not created")
            }

            manager.startOrOpen(runtime)
            if initialPorts[workspace.primaryPort ?? 4_567] == true {
                guard waitUntil(timeout: 4, condition: { runtime.state == .runningExternal }) else {
                    throw InteractionTestError.failed("an existing workspace hub was not safely reused")
                }
                print("PASS: existing workspace reused; no process was stopped")
                return 0
            }

            guard waitUntil(timeout: 45, condition: { runtime.state == .runningOwned }) else {
                throw InteractionTestError.failed("workspace did not become ready")
            }
            guard waitUntil(timeout: 45, condition: {
                workspace.expectedPorts.allSatisfy(LocalToolsManager.portIsOpen)
            }) else {
                manager.stop(runtime)
                _ = waitUntil(timeout: 8, condition: { runtime.state == .stopped })
                throw InteractionTestError.failed("not every workspace service became ready")
            }

            manager.stop(runtime)
            guard waitUntil(timeout: 10, condition: { runtime.state == .stopped }) else {
                throw InteractionTestError.failed("workspace process did not stop cleanly")
            }
            guard LocalToolsManager.portIsOpen(workspace.primaryPort ?? 4_567) == false else {
                throw InteractionTestError.failed("Vaulty-owned workspace port remained open after stop")
            }
            for (port, wasOpen) in initialPorts where wasOpen {
                guard LocalToolsManager.portIsOpen(port) else {
                    throw InteractionTestError.failed("Vaulty stopped reused service on port \(port)")
                }
            }

            print("PASS: workspace started, all four services became ready, Vaulty ended only its owned hub process, and reused services stayed running")
            return 0
        } catch {
            fputs("FAIL: live tools smoke test — \(error)\n", stderr)
            return 1
        }
    }

    @MainActor
    static func testLocalToolsLifecycle(in directory: URL) throws {
        try testLocalToolsAsyncRaces(in: directory)
        let defaults = LocalToolDefinition.defaults()
        guard defaults.map(\.name) == ["bb hub", "Workspace hub"],
              defaults[1].links.map(\.name) == ["Hub", "Dashboard", "Analytics", "Marketing"] else {
            throw InteractionTestError.failed("default local tools do not include bb and the complete workspace hub")
        }

        let port = try reserveLocalPort()
        let secondaryPort = try reserveLocalPort()
        var holdSecondaryOpen = false
        let catalog = LocalToolCatalog(fileURL: directory.appendingPathComponent("tools.json"))
        let manager = LocalToolsManager(
            catalog: catalog,
            defaults: [],
            supervisorExecutableURL: Bundle.main.executableURL,
            runDirectory: directory.appendingPathComponent("runs", isDirectory: true),
            logDirectory: directory.appendingPathComponent("logs", isDirectory: true),
            startsStatusTimer: false,
            opensWhenReady: false,
            portProbe: { ports, callback in
                let states = Dictionary(uniqueKeysWithValues: ports.map {
                    ($0, $0 == secondaryPort ? holdSecondaryOpen : LocalToolsManager.portIsOpen($0))
                })
                DispatchQueue.main.async { callback(states) }
            },
            openURL: { _ in true }
        )
        let definition = LocalToolDefinition(
            name: "Fixture server",
            detail: "Owned lifecycle test",
            workingDirectory: directory.path,
            executablePath: "/usr/bin/python3",
            arguments: ["-m", "http.server", String(port), "--bind", "127.0.0.1"],
            links: [LocalToolLink(name: "Fixture", urlString: "http://127.0.0.1:\(port)")],
            expectedPorts: [port, secondaryPort],
            primaryPort: port
        )
        let invalidLink = LocalToolDefinition(
            name: "Invalid fixture",
            detail: "Must be rejected",
            workingDirectory: directory.path,
            executablePath: "/usr/bin/python3",
            arguments: [],
            links: [LocalToolLink(name: "Broken", urlString: "http://localhost:")],
            expectedPorts: []
        )
        do {
            try manager.add(invalidLink)
            throw InteractionTestError.failed("malformed local tool URL was accepted")
        } catch is LocalToolError {
            // Expected validation failure.
        }
        try manager.add(definition)
        guard let runtime = manager.tools.first else {
            throw InteractionTestError.failed("added local tool was not persisted in memory")
        }

        manager.startOrOpen(runtime)
        guard waitUntil(timeout: 10, condition: { runtime.state == .runningOwned }) else {
            throw InteractionTestError.failed("Vaulty did not start and own the fixture tool")
        }
        defer {
            if runtime.isOwned {
                manager.stop(runtime)
                _ = waitUntil(timeout: 6, condition: { runtime.state == .stopped })
            }
        }

        let oldPID = runtime.ownedPID
        let recordURL = directory.appendingPathComponent("runs/\(runtime.id.uuidString).state.json")
        holdSecondaryOpen = true
        manager.restart(runtime)
        manager.refreshStatuses()
        guard waitUntil(timeout: 5, condition: {
            guard let oldPID else { return false }
            return kill(oldPID, 0) == -1 && errno == ESRCH && !LocalToolsManager.portIsOpen(port)
        }) else { throw InteractionTestError.failed("restart did not stop its old fixture supervisor") }
        try checkApp(runtime.state == .stopping && runtime.ownedPID == oldPID,
                     "restart relaunched before every expected port closed")
        try checkApp(FileManager.default.fileExists(atPath: recordURL.path),
                     "restart discarded ownership before verified port closure")
        holdSecondaryOpen = false
        guard waitUntil(timeout: 10, condition: { runtime.state == .runningOwned && runtime.ownedPID != oldPID }) else {
            throw InteractionTestError.failed("restart did not launch a fresh PID after verified exit and port closure")
        }
        print("PASS: restart waits for supervisor exit and all owned ports closing, retains ownership, and launches a fresh PID")

        // Failed readiness must expose safe recovery without starting a duplicate.
        runtime.state = .failed
        runtime.statusText = "Fixture recovery"
        manager.refreshStatuses()
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
        try checkApp(runtime.state == .failed && runtime.canControlOwned, "status refresh erased owned failure recovery")
        manager.startOrOpen(runtime)
        try checkApp(runtime.state == .failed, "Retry duplicated a failed owned service")
        let recoveryPID = runtime.ownedPID
        manager.restart(runtime)
        guard waitUntil(timeout: 10, condition: { runtime.state == .runningOwned && runtime.ownedPID != recoveryPID }) else {
            throw InteractionTestError.failed("failed owned service could not recover with Restart")
        }
        print("PASS: failed owned service keeps Stop/Restart recovery and cannot duplicate through Retry")

        let refreshedPID = runtime.ownedPID
        runtime.state = .failed
        runtime.errorText = "Stop or Restart the owned service before retrying."
        manager.refreshStatus(runtime)
        guard waitUntil(timeout: 4, condition: { runtime.state == .runningOwned }) else {
            throw InteractionTestError.failed("explicit status refresh did not recover a verified ready owned service")
        }
        try checkApp(runtime.ownedPID == refreshedPID && runtime.errorText == nil,
                     "status recovery changed ownership or retained a stale failure")
        manager.startOrOpen(runtime)
        try checkApp(runtime.ownedPID == refreshedPID && runtime.state == .runningOwned,
                     "opening a recovered service launched a duplicate")
        print("PASS: explicit status refresh recovers a verified ready service, clears its error, and Open preserves its PID")

        let reloaded = LocalToolCatalog(fileURL: catalog.fileURL).load(defaults: [])
        guard reloaded.count == 1, reloaded[0].name == "Fixture server" else {
            throw InteractionTestError.failed("local tool catalog did not reload its saved tool")
        }

        let reattachedManager = LocalToolsManager(
            catalog: catalog,
            defaults: [],
            supervisorExecutableURL: Bundle.main.executableURL,
            runDirectory: directory.appendingPathComponent("runs", isDirectory: true),
            logDirectory: directory.appendingPathComponent("logs", isDirectory: true),
            startsStatusTimer: false,
            opensWhenReady: false,
            openURL: { _ in true }
        )
        guard let reattachedRuntime = reattachedManager.tools.first,
              waitUntil(timeout: 4, condition: { reattachedRuntime.state == .runningOwned }) else {
            throw InteractionTestError.failed("a relaunched Vaulty manager did not recover ownership of its supervisor")
        }

        try checkApp(reattachedRuntime.ownedPID == runtime.ownedPID, "restored ownership changed supervisor PID")
        reattachedRuntime.state = .failed
        reattachedManager.stop(reattachedRuntime)
        guard waitUntil(timeout: 6, condition: { reattachedRuntime.state == .stopped }) else {
            throw InteractionTestError.failed("reattached Vaulty manager did not stop its owned fixture process group")
        }
        print("PASS: restored ownership stops an owned failed fixture without touching external services")
        try reattachedManager.remove(reattachedRuntime)
        guard LocalToolCatalog(fileURL: catalog.fileURL).load(defaults: []).isEmpty else {
            throw InteractionTestError.failed("removed local tool remained in the persisted catalog")
        }
    }

}
