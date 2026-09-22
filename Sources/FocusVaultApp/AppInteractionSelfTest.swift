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
                guardStorage: guardStorage
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

            try testDashboardWidgetPersistence()
            try testLocalToolsLifecycle(in: directory)

            print("PASS: verified explicit YouTube unlock, selectable task hub, free-position/resizable dashboard persistence, task clock actions, and configurable local-tool lifecycle all changed verified state")
            return 0
        } catch {
            fputs("FAIL: app interaction smoke test — \(error)\n", stderr)
            return 1
        }
    }

    @MainActor
    private static func testDashboardWidgetPersistence() throws {
        let suiteName = "VaultyDashboardSelfTest.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw InteractionTestError.failed("could not create isolated dashboard defaults")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let key = "widget-canvas"
        let layout = DashboardLayoutModel(defaults: defaults, key: key, legacyKey: "legacy-order")
        try checkApp(
            Set(layout.order) == Set(DashboardWidgetKind.allCases),
            "dashboard did not start with every widget"
        )

        layout.move(.localTools, toColumn: 2, row: 10)
        var tools = layout.placement(for: .localTools)
        try checkApp(tools.column == 2 && tools.row == 10, "dashboard widget did not move to an exact slot")

        layout.resize(.localTools, width: 4, height: 3)
        tools = layout.placement(for: .localTools)
        try checkApp(tools.width == 4 && tools.height == 3, "dashboard widget did not resize")
        try checkApp(tools.column == 0, "wide widget was not clamped inside the canvas")
        try checkApp(!hasDashboardOverlap(layout.placements), "dashboard collision resolution left overlapping widgets")

        let beforeCycle = layout.placement(for: .intention).span
        layout.cycleSize(of: .intention)
        try checkApp(
            layout.placement(for: .intention).span != beforeCycle,
            "dashboard resize handle cycle did not change size"
        )
        try checkApp(!hasDashboardOverlap(layout.placements), "size cycling created an overlap")

        let restored = DashboardLayoutModel(defaults: defaults, key: key, legacyKey: "legacy-order")
        try checkApp(
            restored.placement(for: .localTools) == tools,
            "dashboard position and size did not persist"
        )

        defaults.set(
            [DashboardWidgetKind.localTools.rawValue, DashboardWidgetKind.intention.rawValue],
            forKey: "legacy-order"
        )
        let migrated = DashboardLayoutModel(
            defaults: defaults,
            key: "migrated-widget-canvas",
            legacyKey: "legacy-order"
        )
        try checkApp(migrated.order.first == .localTools, "legacy widget order did not migrate")
        try checkApp(!hasDashboardOverlap(migrated.placements), "migrated dashboard contains overlaps")

        restored.reset()
        try checkApp(
            restored.placements == DashboardWidgetKind.allCases.map(\.defaultPlacement),
            "dashboard reset did not restore default positions and sizes"
        )
    }

    private static func hasDashboardOverlap(_ placements: [DashboardWidgetPlacement]) -> Bool {
        for leftIndex in placements.indices {
            for rightIndex in placements.indices where rightIndex > leftIndex {
                let left = placements[leftIndex]
                let right = placements[rightIndex]
                let overlaps = left.column < right.column + right.width
                    && left.column + left.width > right.column
                    && left.row < right.row + right.height
                    && left.row + left.height > right.row
                if overlaps { return true }
            }
        }
        return false
    }

    private static func checkApp(_ condition: Bool, _ message: String) throws {
        guard condition else { throw InteractionTestError.failed(message) }
    }

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
    private static func testLocalToolsLifecycle(in directory: URL) throws {
        let defaults = LocalToolDefinition.defaults()
        guard defaults.map(\.name) == ["bb hub", "Workspace hub"],
              defaults[1].links.map(\.name) == ["Hub", "Dashboard", "Analytics", "Marketing"] else {
            throw InteractionTestError.failed("default local tools do not include bb and the complete workspace hub")
        }

        let port = try reserveLocalPort()
        let catalog = LocalToolCatalog(fileURL: directory.appendingPathComponent("tools.json"))
        let manager = LocalToolsManager(
            catalog: catalog,
            defaults: [],
            supervisorExecutableURL: Bundle.main.executableURL,
            runDirectory: directory.appendingPathComponent("runs", isDirectory: true),
            logDirectory: directory.appendingPathComponent("logs", isDirectory: true),
            startsStatusTimer: false,
            opensWhenReady: false,
            openURL: { _ in true }
        )
        let definition = LocalToolDefinition(
            name: "Fixture server",
            detail: "Owned lifecycle test",
            workingDirectory: directory.path,
            executablePath: "/usr/bin/python3",
            arguments: ["-m", "http.server", String(port), "--bind", "127.0.0.1"],
            links: [LocalToolLink(name: "Fixture", urlString: "http://127.0.0.1:\(port)")],
            expectedPorts: [port],
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
            if runtime.state == .runningOwned {
                manager.stop(runtime)
                _ = waitUntil(timeout: 6, condition: { runtime.state == .stopped })
            }
        }

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

        reattachedManager.stop(reattachedRuntime)
        guard waitUntil(timeout: 6, condition: { reattachedRuntime.state == .stopped }) else {
            throw InteractionTestError.failed("reattached Vaulty manager did not stop its owned fixture process group")
        }
        try reattachedManager.remove(reattachedRuntime)
        guard LocalToolCatalog(fileURL: catalog.fileURL).load(defaults: []).isEmpty else {
            throw InteractionTestError.failed("removed local tool remained in the persisted catalog")
        }
    }

    @MainActor
    private static func waitUntil(timeout: TimeInterval, condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        return condition()
    }

    private static func reserveLocalPort() throws -> Int {
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

private enum InteractionTestError: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case let .failed(message):
            return message
        }
    }
}
