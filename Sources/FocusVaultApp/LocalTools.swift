import AppKit
import Combine
import Darwin
import Foundation

struct LocalToolLink: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
    var urlString: String

    init(id: UUID = UUID(), name: String, urlString: String) {
        self.id = id
        self.name = name
        self.urlString = urlString
    }

    var url: URL? { URL(string: urlString) }
}

enum LocalToolUpdateMode: String, Codable, CaseIterable, Equatable {
    case none
    case gitRemote
    case npmPackage

    var title: String {
        switch self {
        case .none: return "None"
        case .gitRemote: return "Git remote"
        case .npmPackage: return "npm package"
        }
    }
}

struct LocalToolDefinition: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var detail: String
    var iconName: String
    var workingDirectory: String
    var executablePath: String
    var arguments: [String]
    var links: [LocalToolLink]
    var expectedPorts: [Int]
    var primaryPort: Int?
    var allowsPartialReuse: Bool
    var updateMode: LocalToolUpdateMode
    var updateIdentifier: String

    init(
        id: UUID = UUID(),
        name: String,
        detail: String,
        iconName: String = "hammer.fill",
        workingDirectory: String,
        executablePath: String,
        arguments: [String],
        links: [LocalToolLink],
        expectedPorts: [Int],
        primaryPort: Int? = nil,
        allowsPartialReuse: Bool = false,
        updateMode: LocalToolUpdateMode = .none,
        updateIdentifier: String = ""
    ) {
        self.id = id
        self.name = name
        self.detail = detail
        self.iconName = iconName
        self.workingDirectory = workingDirectory
        self.executablePath = executablePath
        self.arguments = arguments
        self.links = links
        self.expectedPorts = expectedPorts
        self.primaryPort = primaryPort ?? expectedPorts.first
        self.allowsPartialReuse = allowsPartialReuse
        self.updateMode = updateMode
        self.updateIdentifier = updateIdentifier
    }

    var primaryURL: URL? { links.first?.url }

    func validated(fileManager: FileManager = .default) throws -> LocalToolDefinition {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanDetail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        let cwd = expandedPath(workingDirectory)
        let executable = expandedPath(executablePath)
        let normalizedPorts = Array(Set(expectedPorts)).sorted()

        guard !cleanName.isEmpty, cleanName.count <= 60 else {
            throw LocalToolError.invalidDefinition("Enter a tool name up to 60 characters.")
        }
        guard !cwd.isEmpty, fileManager.fileExists(atPath: cwd) else {
            throw LocalToolError.invalidDefinition("The working directory does not exist.")
        }
        guard executable.hasPrefix("/"), fileManager.isExecutableFile(atPath: executable) else {
            throw LocalToolError.invalidDefinition("Choose an absolute executable path that exists.")
        }
        guard !links.isEmpty, links.allSatisfy({ link in
            let raw = link.urlString.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !link.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !raw.hasSuffix(":"),
                  let components = URLComponents(string: raw),
                  let scheme = components.scheme,
                  scheme == "http" || scheme == "https",
                  components.host?.isEmpty == false else {
                return false
            }
            return true
        }) else {
            throw LocalToolError.invalidDefinition("Add at least one valid http or https link.")
        }
        guard normalizedPorts.allSatisfy({ (1...65_535).contains($0) }) else {
            throw LocalToolError.invalidDefinition("Ports must be between 1 and 65535.")
        }
        if let primaryPort, !normalizedPorts.contains(primaryPort) {
            throw LocalToolError.invalidDefinition("The primary port must be one of the expected ports.")
        }
        if updateMode == .npmPackage,
           updateIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw LocalToolError.invalidDefinition("Enter the npm package name used for update checks.")
        }

        var validated = self
        validated.name = cleanName
        validated.detail = cleanDetail
        validated.workingDirectory = cwd
        validated.executablePath = executable
        validated.expectedPorts = normalizedPorts
        validated.updateIdentifier = updateIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        return validated
    }

    private func expandedPath(_ value: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return value
            .replacingOccurrences(of: "$HOME", with: home)
            .replacingOccurrences(of: "~", with: home, options: [.anchored])
    }

    static func defaults(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        workspaceRoot: URL? = nil
    ) -> [LocalToolDefinition] {
        let bbID = UUID(uuidString: "BBA00000-0000-4000-8000-000000000001")!
        let workspaceID = UUID(uuidString: "11FED0C0-0000-4000-8000-000000000002")!
        let workspaceRootPath = (workspaceRoot
            ?? home.appendingPathComponent("Documents/Workspace", isDirectory: true)).path

        return [
            LocalToolDefinition(
                id: bbID,
                name: "bb hub",
                detail: "Local agent workspace",
                iconName: "square.grid.2x2.fill",
                workingDirectory: home.path,
                executablePath: "/usr/bin/env",
                arguments: [
                    "npx",
                    "--yes",
                    "--allow-scripts=better-sqlite3,node-pty,@parcel/watcher",
                    "bb-app@latest"
                ],
                links: [
                    LocalToolLink(name: "bb hub", urlString: "http://127.0.0.1:38886")
                ],
                expectedPorts: [38_886],
                primaryPort: 38_886,
                updateMode: .npmPackage,
                updateIdentifier: "bb-app"
            ),
            LocalToolDefinition(
                id: workspaceID,
                name: "Workspace hub",
                detail: "Dashboard · Analytics · Marketing",
                iconName: "rectangle.3.group.fill",
                workingDirectory: workspaceRootPath,
                executablePath: "/usr/bin/env",
                arguments: ["npm", "run", "workspace"],
                links: [
                    LocalToolLink(name: "Hub", urlString: "http://localhost:4567"),
                    LocalToolLink(name: "Dashboard", urlString: "http://localhost:4567/?view=dashboard"),
                    LocalToolLink(name: "Analytics", urlString: "http://localhost:5173"),
                    LocalToolLink(name: "Marketing", urlString: "https://localhost:3001")
                ],
                expectedPorts: [4_567, 5_173, 3_000, 3_001],
                primaryPort: 4_567,
                allowsPartialReuse: true
            )
        ]
    }
}

enum LocalToolState: Equatable {
    case stopped
    case checking
    case starting
    case runningOwned
    case runningExternal
    case stopping
    case failed
}

enum LocalToolError: Error, LocalizedError, Equatable {
    case invalidDefinition(String)
    case partiallyRunning([Int])
    case supervisorUnavailable
    case launchFailed(String)
    case stopRefused
    case updateFailed(String)

    var errorDescription: String? {
        switch self {
        case let .invalidDefinition(message): return message
        case let .partiallyRunning(ports):
            return "Only these expected ports are running: \(ports.map(String.init).joined(separator: ", ")). Stop the incomplete tool before starting it."
        case .supervisorUnavailable:
            return "Vaulty could not locate its process supervisor."
        case let .launchFailed(message): return message
        case .stopRefused:
            return "Vaulty refused to stop a process it could not verify as its own."
        case let .updateFailed(message): return message
        }
    }
}

final class LocalToolRuntime: ObservableObject, Identifiable, @unchecked Sendable {
    let id: UUID
    @Published var definition: LocalToolDefinition
    @Published var state: LocalToolState = .stopped
    @Published var statusText = "Stopped"
    @Published var errorText: String?
    @Published var updateText: String?
    @Published var isCheckingUpdate = false

    fileprivate var supervisorProcess: Process?
    fileprivate var supervisorPID: pid_t?
    fileprivate var logHandle: FileHandle?
    fileprivate var readinessWorkItem: DispatchWorkItem?
    fileprivate var generation = UUID()
    fileprivate var statusGeneration = UUID()
    fileprivate var restartPending = false
    fileprivate var reusedPorts: Set<Int> = []

    var ownedPID: pid_t? { supervisorPID }
    var canCancel: Bool { state == .checking || state == .starting }
    var canControlOwned: Bool { supervisorPID != nil && state != .stopping && !canCancel }

    init(definition: LocalToolDefinition) {
        id = definition.id
        self.definition = definition
    }

    var isRunning: Bool {
        state == .runningOwned || state == .runningExternal
    }

    var isOwned: Bool { supervisorPID != nil }

    var actionTitle: String {
        switch state {
        case .checking, .starting: return "Starting…"
        case .runningOwned, .runningExternal: return "Open"
        case .stopping: return "Stopping…"
        case .failed: return "Retry"
        case .stopped: return "Start"
        }
    }
}

private struct LocalToolCatalogFile: Codable {
    let version: Int
    var tools: [LocalToolDefinition]
}

struct LocalToolCatalog {
    let fileURL: URL

    init(fileURL: URL = LocalToolCatalog.defaultURL) {
        self.fileURL = fileURL
    }

    static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Vaulty", isDirectory: true)
            .appendingPathComponent("tools.json")
    }

    func load(defaults: [LocalToolDefinition]) -> [LocalToolDefinition] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            try? save(defaults)
            return defaults
        }
        guard let data = try? Data(contentsOf: fileURL),
              let file = try? JSONDecoder().decode(LocalToolCatalogFile.self, from: data),
              file.version == 1 else {
            // Preserve a malformed catalog for manual recovery instead of
            // silently overwriting the user's configured tools.
            return defaults
        }
        return file.tools
    }

    func save(_ tools: [LocalToolDefinition]) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(LocalToolCatalogFile(version: 1, tools: tools))
        try data.write(to: fileURL, options: .atomic)
    }
}

private struct LocalToolSupervisorConfiguration: Codable {
    let executablePath: String
    let arguments: [String]
    let workingDirectory: String
    let logPath: String
    let environmentPath: String
}

private struct LocalToolRunRecord: Codable {
    let toolID: UUID
    let supervisorPID: pid_t
    let supervisorExecutablePath: String
    let configurationPath: String
    let startedAt: Date
    var reusedPorts: [Int]? = nil
    var startSeconds: UInt64? = nil
    var startMicroseconds: UInt64? = nil
}

enum LocalToolProcessSupervisor {
    static func run(configurationPath: String) -> Int32 {
        let handledSignals = [SIGTERM, SIGINT, SIGHUP]
        handledSignals.forEach { signal($0, SIG_IGN) }
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: configurationPath))
            let config = try JSONDecoder().decode(LocalToolSupervisorConfiguration.self, from: data)
            guard config.executablePath.hasPrefix("/"),
                  FileManager.default.isExecutableFile(atPath: config.executablePath),
                  FileManager.default.fileExists(atPath: config.workingDirectory) else {
                throw LocalToolError.invalidDefinition("Supervisor configuration is invalid.")
            }

            guard setpgid(0, 0) == 0 || getpgrp() == getpid() else {
                throw LocalToolError.launchFailed("Vaulty could not create an isolated process group.")
            }

            let logURL = URL(fileURLWithPath: config.logPath)
            try FileManager.default.createDirectory(
                at: logURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if !FileManager.default.fileExists(atPath: logURL.path) {
                FileManager.default.createFile(atPath: logURL.path, contents: Data())
            }
            let log = try FileHandle(forWritingTo: logURL)
            try log.seekToEnd()
            defer { try? log.close() }

            let child = Process()
            child.executableURL = URL(fileURLWithPath: config.executablePath)
            child.arguments = config.arguments
            child.currentDirectoryURL = URL(fileURLWithPath: config.workingDirectory, isDirectory: true)
            child.standardOutput = log
            child.standardError = log
            var environment = ProcessInfo.processInfo.environment
            environment["PATH"] = config.environmentPath
            child.environment = environment
            // Dispositions were installed before establishing the group, so an
            // immediate Cancel cannot bypass descendant bookkeeping.
            try child.run()
            let childGroup = getpgid(child.processIdentifier)
            if childGroup > 1, childGroup != getpgrp() {
                try String(childGroup).write(toFile: configurationPath + ".child-pgid", atomically: true, encoding: .utf8)
            }

            let signalQueue = DispatchQueue(label: "com.jacksongb.vaulty.tool-supervisor-signals")
            let signalSources = handledSignals.map { signalNumber -> DispatchSourceSignal in
                signal(signalNumber, SIG_IGN)
                let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: signalQueue)
                source.setEventHandler {
                    if childGroup > 1, childGroup != getpgrp() {
                        _ = kill(-childGroup, SIGTERM)
                    } else if child.isRunning {
                        child.terminate()
                    }
                }
                source.resume()
                return source
            }

            // Keep ownership alive until the isolated child group has drained,
            // including descendants that outlive the command's immediate child.
            child.waitUntilExit()
            if childGroup > 1, childGroup != getpgrp() {
                while kill(-childGroup, 0) == 0 || errno == EPERM {
                    Thread.sleep(forTimeInterval: 0.1)
                }
            }
            signalSources.forEach { $0.cancel() }
            return child.terminationStatus
        } catch {
            let message = "Vaulty tool supervisor failed: \(error.localizedDescription)\n"
            FileHandle.standardError.write(Data(message.utf8))
            return 1
        }
    }
}

final class LocalToolsManager: ObservableObject {
    let caffeinate = CaffeinateController()
    @Published private(set) var tools: [LocalToolRuntime]
    @Published var isPresentingManager = false
    @Published var isPresentingAddTool = false
    @Published private(set) var catalogError: String?

    private let catalog: LocalToolCatalog
    private let supervisorExecutableURL: URL?
    private let runDirectory: URL
    private let logDirectory: URL
    private let openURL: (URL) -> Bool
    private let opensWhenReady: Bool
    private var statusTimer: Timer?
    private let portProbe: (([Int], @escaping ([Int: Bool]) -> Void) -> Void)?
    private let externalBBStop: (LocalToolDefinition) throws -> Void

    init(
        catalog: LocalToolCatalog = LocalToolCatalog(),
        defaults: [LocalToolDefinition] = LocalToolDefinition.defaults(),
        supervisorExecutableURL: URL? = Bundle.main.executableURL,
        runDirectory: URL? = nil,
        logDirectory: URL? = nil,
        startsStatusTimer: Bool = true,
        opensWhenReady: Bool = true,
        portProbe: (([Int], @escaping ([Int: Bool]) -> Void) -> Void)? = nil,
        externalBBStop: @escaping (LocalToolDefinition) throws -> Void = { _ = try BBExternalLifecycle.stop(definition: $0) },
        openURL: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) }
    ) {
        self.portProbe = portProbe
        self.externalBBStop = externalBBStop
        self.catalog = catalog
        self.supervisorExecutableURL = supervisorExecutableURL
        self.runDirectory = runDirectory ?? catalog.fileURL.deletingLastPathComponent().appendingPathComponent("ToolRuns", isDirectory: true)
        self.logDirectory = logDirectory ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Vaulty", isDirectory: true)
        self.opensWhenReady = opensWhenReady
        self.openURL = openURL
        tools = catalog.load(defaults: defaults).map(LocalToolRuntime.init)
        restoreOwnedRuns()
        if startsStatusTimer {
            statusTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in self.refreshStatuses() }
            }
        }
        refreshStatuses()
    }

    deinit {
        statusTimer?.invalidate()
    }

    func runtime(id: UUID) -> LocalToolRuntime? {
        tools.first { $0.id == id }
    }

    func add(_ definition: LocalToolDefinition) throws {
        let validated = try definition.validated()
        guard runtime(id: validated.id) == nil else {
            throw LocalToolError.invalidDefinition("That tool already exists.")
        }
        tools.append(LocalToolRuntime(definition: validated))
        try persist()
        refreshStatuses()
    }

    func remove(_ runtime: LocalToolRuntime) throws {
        guard !runtime.isOwned,
              runtime.state != .checking,
              runtime.state != .starting,
              runtime.state != .stopping else {
            throw LocalToolError.invalidDefinition("Stop this Vaulty-owned process before removing the tool.")
        }
        tools.removeAll { $0.id == runtime.id }
        removeRunRecord(for: runtime.id)
        try persist()
    }

    func startOrOpen(_ runtime: LocalToolRuntime) {
        guard runtime.state != .checking,
              runtime.state != .starting,
              runtime.state != .stopping else { return }
        if runtime.isRunning {
            openPrimaryLink(runtime)
            return
        }

        guard runtime.supervisorPID == nil else {
            runtime.errorText = "Stop or Restart the owned service before retrying."
            return
        }
        let generation = beginOperation(runtime)
        runtime.state = .checking
        runtime.statusText = "Checking local ports…"
        runtime.errorText = nil
        probePorts(runtime.definition.expectedPorts) { [weak self, weak runtime] states in
            guard let self, let runtime, runtime.generation == generation, runtime.state == .checking else { return }
            let openPorts = states.filter(\.value).map(\.key).sorted()
            if let primary = runtime.definition.primaryPort, states[primary] == true {
                runtime.state = .runningExternal
                runtime.statusText = BBExternalLifecycle.matches(runtime.definition)
                    ? "External bb · restart available"
                    : "External · use its original launcher"
                self.openPrimaryLink(runtime)
                return
            }
            if !openPorts.isEmpty, !runtime.definition.allowsPartialReuse {
                self.fail(runtime, LocalToolError.partiallyRunning(openPorts))
                return
            }
            runtime.reusedPorts = Set(openPorts)
            do {
                try self.launch(runtime)
            } catch {
                self.fail(runtime, error)
            }
        }
    }

    @discardableResult
    private func beginOperation(_ runtime: LocalToolRuntime) -> UUID {
        runtime.generation = UUID()
        runtime.statusGeneration = UUID()
        runtime.readinessWorkItem?.cancel()
        runtime.readinessWorkItem = nil
        return runtime.generation
    }

    func cancel(_ runtime: LocalToolRuntime) {
        guard runtime.canCancel else { return }
        if runtime.supervisorPID != nil {
            stop(runtime)
        } else {
            beginOperation(runtime)
            runtime.state = .stopped
            runtime.statusText = "Cancelled"
            runtime.errorText = nil
        }
    }

    func restart(_ runtime: LocalToolRuntime) {
        if runtime.state == .runningExternal, BBExternalLifecycle.matches(runtime.definition) {
            stopExternalBB(runtime, restarting: true)
            return
        }
        guard runtime.canControlOwned else {
            runtime.errorText = "External services must be restarted in their original launcher."
            return
        }
        stop(runtime, restarting: true)
    }

    /// UI callers must confirm interruption before invoking this external path.
    func stop(_ runtime: LocalToolRuntime) {
        if runtime.state == .runningExternal, BBExternalLifecycle.matches(runtime.definition) {
            stopExternalBB(runtime, restarting: false)
            return
        }
        stop(runtime, restarting: false)
    }

    private func stopExternalBB(_ runtime: LocalToolRuntime, restarting: Bool) {
        guard runtime.state == .runningExternal, BBExternalLifecycle.matches(runtime.definition) else { return }
        let generation = beginOperation(runtime)
        runtime.restartPending = restarting
        runtime.reusedPorts = []
        runtime.state = .stopping
        runtime.statusText = restarting ? "Restarting bb…" : "Stopping bb…"
        runtime.errorText = nil
        let definition = runtime.definition
        let stopCommand = externalBBStop
        DispatchQueue.global(qos: .utility).async { [weak self, weak runtime] in
            let result = Result { try stopCommand(definition) }
            DispatchQueue.main.async {
                guard let self, let runtime, runtime.generation == generation, runtime.state == .stopping else { return }
                switch result {
                case .success:
                    self.verifyExternalBBStopped(runtime, generation: generation, attempt: 0)
                case let .failure(error):
                    runtime.restartPending = false
                    // Retain external recovery controls instead of pretending to own bb.
                    runtime.state = .runningExternal
                    runtime.statusText = "External bb · stop failed"
                    runtime.errorText = error.localizedDescription
                }
            }
        }
    }

    private func verifyExternalBBStopped(_ runtime: LocalToolRuntime, generation: UUID, attempt: Int) {
        guard runtime.generation == generation, runtime.state == .stopping else { return }
        probePorts(runtime.definition.expectedPorts) { [weak self, weak runtime] states in
            guard let self, let runtime, runtime.generation == generation, runtime.state == .stopping else { return }
            if states.values.allSatisfy({ !$0 }) {
                let restart = runtime.restartPending
                runtime.restartPending = false
                runtime.state = .stopped
                runtime.statusText = "bb stopped"
                if restart { self.startOrOpen(runtime) }
                return
            }
            guard attempt < 40 else {
                runtime.restartPending = false
                runtime.state = .runningExternal
                runtime.statusText = "External bb · port still open"
                runtime.errorText = "bb's port did not close after its stop command. No new instance was launched. Retry Stop or check its original launcher."
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self, weak runtime] in
                guard let self, let runtime else { return }
                self.verifyExternalBBStopped(runtime, generation: generation, attempt: attempt + 1)
            }
        }
    }

    private func stop(_ runtime: LocalToolRuntime, restarting: Bool) {
        guard runtime.supervisorPID != nil, runtime.state != .stopping else {
            runtime.errorText = "Vaulty can stop only verified process groups it started."
            return
        }
        let generation = beginOperation(runtime)
        runtime.restartPending = restarting
        runtime.state = .stopping
        runtime.statusText = restarting ? "Restarting · waiting for exit and closed ports…" : "Stopping owned process…"
        runtime.errorText = nil
        requestStop(runtime, generation: generation, attempt: 0)
    }

    private func requestStop(_ runtime: LocalToolRuntime, generation: UUID, attempt: Int) {
        guard runtime.generation == generation, let pid = runtime.supervisorPID else { return }
        if isVerifiedSupervisor(pid: pid) {
            guard kill(-pid, SIGTERM) == 0 else {
                fail(runtime, LocalToolError.stopRefused)
                return
            }
            scheduleStopVerification(runtime, generation: generation, attempt: 0)
        } else if ownedGroupsExited(runtime) {
            scheduleStopVerification(runtime, generation: generation, attempt: 0)
        } else if attempt < 20 {
            // Process.run returns before the supervisor establishes its group.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self, weak runtime] in
                guard let self, let runtime else { return }
                self.requestStop(runtime, generation: generation, attempt: attempt + 1)
            }
        } else {
            fail(runtime, LocalToolError.stopRefused)
        }
    }

    func refreshStatus(_ runtime: LocalToolRuntime) { refreshStatuses(only: runtime.id) }

    func openPrimaryLink(_ runtime: LocalToolRuntime) {
        guard let url = runtime.definition.primaryURL else {
            runtime.errorText = "This tool has no valid local link."
            return
        }
        if !openURL(url) {
            runtime.errorText = "Vaulty could not open \(url.absoluteString)."
        }
    }

    func open(_ link: LocalToolLink, for runtime: LocalToolRuntime) {
        guard let url = link.url, openURL(url) else {
            runtime.errorText = "Vaulty could not open that link."
            return
        }
    }

    func copy(_ link: LocalToolLink, for runtime: LocalToolRuntime) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(link.urlString, forType: .string)
        runtime.statusText = "Copied \(link.name) link"
    }

    func checkForUpdates(_ runtime: LocalToolRuntime) {
        guard !runtime.isCheckingUpdate else { return }
        runtime.isCheckingUpdate = true
        runtime.updateText = "Checking…"
        let definition = runtime.definition

        DispatchQueue.global(qos: .utility).async {
            let result: Result<String, Error>
            switch definition.updateMode {
            case .none:
                result = .success("No update source configured")
            case .npmPackage:
                result = Self.checkNPMUpdate(package: definition.updateIdentifier)
            case .gitRemote:
                result = Self.checkGitUpdate(directory: definition.workingDirectory)
            }
            DispatchQueue.main.async {
                runtime.isCheckingUpdate = false
                switch result {
                case let .success(message): runtime.updateText = message
                case let .failure(error): runtime.updateText = error.localizedDescription
                }
            }
        }
    }

    func refreshStatuses(only id: UUID? = nil) {
        for runtime in tools where (id == nil || runtime.id == id) && !runtime.canCancel && runtime.state != .stopping {
            let generation = runtime.generation
            let statusGeneration = UUID()
            runtime.statusGeneration = statusGeneration
            probePorts(runtime.definition.expectedPorts) { [weak self, weak runtime] states in
                guard let self, let runtime,
                      runtime.generation == generation, runtime.statusGeneration == statusGeneration,
                      !runtime.canCancel, runtime.state != .stopping else { return }
                let primaryOpen = runtime.definition.primaryPort.map { states[$0] == true }
                    ?? states.values.contains(true)
                if runtime.supervisorPID != nil {
                    if self.ownedGroupsExited(runtime) {
                        self.clearOwnership(runtime)
                    } else {
                        guard runtime.state != .failed else { return }
                        runtime.state = primaryOpen ? .runningOwned : .failed
                        runtime.statusText = primaryOpen ? "Running · started by Vaulty" : "Owned service not ready · Stop or Restart"
                        return
                    }
                }
                if primaryOpen {
                    runtime.state = .runningExternal
                    runtime.statusText = BBExternalLifecycle.matches(runtime.definition)
                    ? "External bb · restart available"
                    : "External · use its original launcher"
                } else if runtime.state != .failed {
                    runtime.state = .stopped
                    runtime.statusText = "Stopped"
                }
            }
        }
    }

    private func launch(_ runtime: LocalToolRuntime) throws {
        guard let supervisorExecutableURL else {
            throw LocalToolError.supervisorUnavailable
        }
        let definition = try runtime.definition.validated()
        try FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)
        let configURL = runDirectory.appendingPathComponent("\(definition.id.uuidString).json")
        try? FileManager.default.removeItem(atPath: configURL.path + ".child-pgid")
        let generation = runtime.generation
        let logURL = logDirectory
            .appendingPathComponent("tool-\(definition.id.uuidString).log")
        let config = LocalToolSupervisorConfiguration(
            executablePath: definition.executablePath,
            arguments: definition.arguments,
            workingDirectory: definition.workingDirectory,
            logPath: logURL.path,
            environmentPath: Self.commandSearchPath
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(config).write(to: configURL, options: .atomic)

        let process = Process()
        process.executableURL = supervisorExecutableURL
        process.arguments = ["--tool-supervisor", configURL.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self, weak runtime] process in
            guard let self, let runtime else { return }
            DispatchQueue.main.async {
                guard runtime.supervisorPID == process.processIdentifier,
                      runtime.generation == generation, runtime.state != .stopping else { return }
                runtime.readinessWorkItem?.cancel()
                if self.ownedGroupsExited(runtime) { self.clearOwnership(runtime) }
                runtime.state = process.terminationStatus == 0 ? .stopped : .failed
                runtime.statusText = process.terminationStatus == 0 ? "Stopped" : "Exited · check the Vaulty tool log"
            }
        }

        runtime.supervisorProcess = process
        runtime.state = .starting
        runtime.statusText = "Starting \(definition.name)…"
        try process.run()
        runtime.supervisorPID = process.processIdentifier
        do {
            let identity = Self.processIdentity(process.processIdentifier)
            try writeRunRecord(
                LocalToolRunRecord(
                    toolID: definition.id,
                    supervisorPID: process.processIdentifier,
                    supervisorExecutablePath: supervisorExecutableURL.path,
                    configurationPath: configURL.path,
                    startedAt: Date(),
                    reusedPorts: Array(runtime.reusedPorts),
                    startSeconds: identity?.pbi_start_tvsec,
                    startMicroseconds: identity?.pbi_start_tvusec
                )
            )
        } catch {
            process.terminate()
            // Retain in-memory ownership even if persistence failed.
            throw error
        }
        waitForReadiness(runtime, generation: generation, attempt: 0)
    }

    private func waitForReadiness(_ runtime: LocalToolRuntime, generation: UUID, attempt: Int) {
        guard runtime.generation == generation, runtime.state == .starting else { return }
        let ports = runtime.definition.expectedPorts
        probePorts(ports) { [weak self, weak runtime] states in
            guard let self, let runtime, runtime.generation == generation, runtime.state == .starting else { return }
            let ready = runtime.definition.primaryPort.map { states[$0] == true }
                ?? states.values.contains(true)
            if ready, runtime.supervisorPID.map({ self.isVerifiedSupervisor(pid: $0) }) == true {
                runtime.state = .runningOwned
                runtime.statusText = "Running · started by Vaulty"
                if self.opensWhenReady {
                    self.openPrimaryLink(runtime)
                }
                return
            }
            guard runtime.supervisorPID.map({ self.isVerifiedSupervisor(pid: $0) || runtime.supervisorProcess?.isRunning == true }) == true else {
                self.fail(runtime, LocalToolError.launchFailed("The tool exited before its local link became ready."))
                return
            }
            guard attempt < 80 else {
                self.fail(runtime, LocalToolError.launchFailed("The tool did not become ready within 40 seconds. Check its Vaulty log."))
                return
            }
            let work = DispatchWorkItem { [weak self, weak runtime] in
                guard let self, let runtime else { return }
                self.waitForReadiness(runtime, generation: generation, attempt: attempt + 1)
            }
            runtime.readinessWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
        }
    }

    private func ownedGroupsExited(_ runtime: LocalToolRuntime) -> Bool {
        guard let pid = runtime.supervisorPID else { return true }
        func absent(_ target: pid_t) -> Bool {
            kill(target, 0) == -1 && errno == ESRCH
        }
        guard absent(pid), absent(-pid), runtime.supervisorProcess?.isRunning != true else { return false }
        let path = runDirectory.appendingPathComponent("\(runtime.id.uuidString).json.child-pgid").path
        if let text = try? String(contentsOfFile: path), let childGroup = Int32(text), childGroup > 1 {
            return absent(-childGroup)
        }
        return true
    }

    private func clearOwnership(_ runtime: LocalToolRuntime) {
        removeRunRecord(for: runtime.id)
        runtime.supervisorProcess = nil
        runtime.supervisorPID = nil
        runtime.logHandle = nil
    }

    private func scheduleStopVerification(_ runtime: LocalToolRuntime, generation: UUID, attempt: Int) {
        guard runtime.generation == generation, runtime.state == .stopping else { return }
        probePorts(runtime.definition.expectedPorts) { [weak self, weak runtime] states in
            guard let self, let runtime, runtime.generation == generation, runtime.state == .stopping else { return }
            let portsClosed = states.allSatisfy { runtime.reusedPorts.contains($0.key) || !$0.value }
            if self.ownedGroupsExited(runtime), portsClosed {
                self.clearOwnership(runtime)
                runtime.state = .stopped
                runtime.statusText = "Stopped by Vaulty"
                let restart = runtime.restartPending
                runtime.restartPending = false
                if restart { self.startOrOpen(runtime) }
                return
            }
            // Retry a graceful signal: the first Cancel may precede signal-source
            // installation. Never escalate or signal an unverified supervisor.
            if let pid = runtime.supervisorPID, self.isVerifiedSupervisor(pid: pid) {
                _ = kill(-pid, SIGTERM)
            }
            guard attempt < 40 else {
                self.fail(runtime, LocalToolError.launchFailed("Exit or port closure could not be verified. Ownership retained; no force-kill or relaunch. Try Stop or Restart."))
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self, weak runtime] in
                guard let self, let runtime else { return }
                self.scheduleStopVerification(runtime, generation: generation, attempt: attempt + 1)
            }
        }
    }

    private func fail(_ runtime: LocalToolRuntime, _ error: Error) {
        beginOperation(runtime)
        runtime.restartPending = false
        runtime.state = .failed
        runtime.statusText = "Needs attention"
        runtime.errorText = error.localizedDescription
    }

    private func restoreOwnedRuns() {
        for runtime in tools {
            guard let record = readRunRecord(for: runtime.id) else { continue }
            guard record.toolID == runtime.id,
                  record.configurationPath == runDirectory.appendingPathComponent("\(runtime.id.uuidString).json").path else {
                continue // Invalid records are preserved for manual recovery, never signalled.
            }
            runtime.supervisorPID = record.supervisorPID
            runtime.reusedPorts = Set(record.reusedPorts ?? [])
            if ownedGroupsExited(runtime) {
                clearOwnership(runtime)
            } else if isVerifiedSupervisor(pid: record.supervisorPID) {
                runtime.state = .starting
                runtime.statusText = "Reconnecting to Vaulty-owned process…"
                waitForReadiness(runtime, generation: runtime.generation, attempt: 0)
            } else {
                runtime.state = .failed
                runtime.statusText = "Ownership retained · process exit not verified"
                runtime.errorText = "Vaulty will not signal an unverified process. Check its original launcher or log."
            }
        }
    }

    private func runRecordURL(for id: UUID) -> URL {
        runDirectory.appendingPathComponent("\(id.uuidString).state.json")
    }

    private func writeRunRecord(_ record: LocalToolRunRecord) throws {
        try FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(record).write(to: runRecordURL(for: record.toolID), options: .atomic)
    }

    private func readRunRecord(for id: UUID) -> LocalToolRunRecord? {
        guard let data = try? Data(contentsOf: runRecordURL(for: id)) else { return nil }
        return try? JSONDecoder().decode(LocalToolRunRecord.self, from: data)
    }

    private func removeRunRecord(for id: UUID) {
        try? FileManager.default.removeItem(at: runRecordURL(for: id))
    }

    private func isVerifiedSupervisor(pid: pid_t) -> Bool {
        guard pid > 1, getpgid(pid) == pid else { return false }
        guard kill(pid, 0) == 0 || errno == EPERM else { return false }

        guard let record = tools.compactMap({ readRunRecord(for: $0.id) }).first(where: {
            $0.supervisorPID == pid && $0.configurationPath == runDirectory.appendingPathComponent("\($0.toolID.uuidString).json").path
        }) else { return false }
        if let seconds = record.startSeconds, let micros = record.startMicroseconds {
            guard let identity = Self.processIdentity(pid), identity.pbi_start_tvsec == seconds,
                  identity.pbi_start_tvusec == micros else { return false }
        }
        // An executable match alone could identify another Vaulty window or a
        // recycled PID. Verify this exact tool-supervisor invocation as well.
        guard Self.processArguments(pid).suffix(2) == ["--tool-supervisor", record.configurationPath] else { return false }
        let expectedPath = URL(fileURLWithPath: record.supervisorExecutablePath)
            .standardizedFileURL.resolvingSymlinksInPath().path

        var buffer = [CChar](repeating: 0, count: 4_096)
        let count = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard count > 0 else { return false }
        let actualPath = URL(fileURLWithPath: String(cString: buffer))
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path
        return expectedPath == actualPath
    }

    private static func processIdentity(_ pid: pid_t) -> proc_bsdinfo? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return info
    }

    private static func processArguments(_ pid: pid_t) -> [String] {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return [] }
        var bytes = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &bytes, &size, nil, 0) == 0 else { return [] }
        let argc = bytes.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
        guard argc > 0 else { return [] }
        var offset = MemoryLayout<Int32>.size
        while offset < size && bytes[offset] != 0 { offset += 1 } // executable path
        while offset < size && bytes[offset] == 0 { offset += 1 } // padding
        var arguments: [String] = []
        for _ in 0..<argc {
            let start = offset
            while offset < size && bytes[offset] != 0 { offset += 1 }
            guard offset < size else { return [] }
            arguments.append(String(decoding: bytes[start..<offset], as: UTF8.self))
            offset += 1
        }
        return arguments
    }

    private func persist() throws {
        try catalog.save(tools.map(\.definition))
    }

    private func probePorts(
        _ ports: [Int],
        completion: @escaping ([Int: Bool]) -> Void
    ) {
        if let portProbe { portProbe(ports, completion); return }
        guard !ports.isEmpty else {
            completion([:])
            return
        }
        DispatchQueue.global(qos: .utility).async {
            var result: [Int: Bool] = [:]
            for port in ports {
                result[port] = Self.portIsOpen(port)
            }
            let resolved = result
            DispatchQueue.main.async { completion(resolved) }
        }
    }

    nonisolated static func portIsOpen(_ port: Int) -> Bool {
        ipv4PortIsOpen(port) || ipv6PortIsOpen(port)
    }

    nonisolated private static func ipv4PortIsOpen(_ port: Int) -> Bool {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(port).bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let flags = fcntl(descriptor, F_GETFL, 0)
        _ = fcntl(descriptor, F_SETFL, flags | O_NONBLOCK)
        let connectResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if connectResult == 0 { return true }
        guard errno == EINPROGRESS else { return false }

        var writeSet = fd_set()
        fdZero(&writeSet)
        fdSet(descriptor, set: &writeSet)
        var timeout = timeval(tv_sec: 0, tv_usec: 300_000)
        let selected = select(descriptor + 1, nil, &writeSet, nil, &timeout)
        guard selected > 0 else { return false }
        var socketError: Int32 = 0
        var length = socklen_t(MemoryLayout<Int32>.size)
        guard getsockopt(descriptor, SOL_SOCKET, SO_ERROR, &socketError, &length) == 0 else {
            return false
        }
        return socketError == 0
    }

    nonisolated private static func ipv6PortIsOpen(_ port: Int) -> Bool {
        let descriptor = socket(AF_INET6, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }

        var address = sockaddr_in6()
        address.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
        address.sin6_family = sa_family_t(AF_INET6)
        address.sin6_port = in_port_t(port).bigEndian
        guard inet_pton(AF_INET6, "::1", &address.sin6_addr) == 1 else { return false }

        let flags = fcntl(descriptor, F_GETFL, 0)
        _ = fcntl(descriptor, F_SETFL, flags | O_NONBLOCK)
        let connectResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in6>.size))
            }
        }
        if connectResult == 0 { return true }
        guard errno == EINPROGRESS else { return false }

        var writeSet = fd_set()
        fdZero(&writeSet)
        fdSet(descriptor, set: &writeSet)
        var timeout = timeval(tv_sec: 0, tv_usec: 300_000)
        let selected = select(descriptor + 1, nil, &writeSet, nil, &timeout)
        guard selected > 0 else { return false }
        var socketError: Int32 = 0
        var length = socklen_t(MemoryLayout<Int32>.size)
        guard getsockopt(descriptor, SOL_SOCKET, SO_ERROR, &socketError, &length) == 0 else {
            return false
        }
        return socketError == 0
    }

    nonisolated private static func fdZero(_ set: inout fd_set) {
        set = fd_set()
    }

    nonisolated private static func fdSet(_ descriptor: Int32, set: inout fd_set) {
        let intOffset = Int(descriptor) / 32
        let bitOffset = Int(descriptor) % 32
        withUnsafeMutableBytes(of: &set) { bytes in
            let words = bytes.bindMemory(to: Int32.self)
            if intOffset < words.count {
                words[intOffset] |= Int32(1 << bitOffset)
            }
        }
    }

    nonisolated private static var commandSearchPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            home.appendingPathComponent(".local/bin").path,
            home.appendingPathComponent(".npm-global/bin").path,
            "/usr/bin",
            "/bin"
        ].joined(separator: ":")
    }

    nonisolated private static func runCommand(
        executable: String,
        arguments: [String],
        directory: String? = nil,
        timeout: TimeInterval = 15
    ) -> Result<String, Error> {
        do {
            let process = Process()
            let output = Pipe()
            let error = Pipe()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardOutput = output
            process.standardError = error
            if let directory {
                process.currentDirectoryURL = URL(fileURLWithPath: directory, isDirectory: true)
            }
            var environment = ProcessInfo.processInfo.environment
            environment["PATH"] = commandSearchPath
            process.environment = environment
            try process.run()

            let deadline = Date().addingTimeInterval(timeout)
            while process.isRunning, Date() < deadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
            if process.isRunning {
                process.terminate()
                throw LocalToolError.updateFailed("Update check timed out.")
            }
            let stdout = String(
                data: output.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let stderr = String(
                data: error.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard process.terminationStatus == 0 else {
                throw LocalToolError.updateFailed(stderr.isEmpty ? "Update check failed." : stderr)
            }
            return .success(stdout)
        } catch {
            return .failure(error)
        }
    }

    nonisolated private static func checkNPMUpdate(package: String) -> Result<String, Error> {
        switch runCommand(executable: "/usr/bin/env", arguments: ["npm", "view", package, "version", "--json"]) {
        case let .success(output):
            let version = output.trimmingCharacters(in: CharacterSet(charactersIn: "\"\n "))
            return .success(version.isEmpty ? "No npm version returned" : "Latest: \(version)")
        case let .failure(error):
            return .failure(error)
        }
    }

    nonisolated private static func checkGitUpdate(directory: String) -> Result<String, Error> {
        let local = runCommand(
            executable: "/usr/bin/git",
            arguments: ["-C", directory, "rev-parse", "HEAD"]
        )
        let branch = runCommand(
            executable: "/usr/bin/git",
            arguments: ["-C", directory, "branch", "--show-current"]
        )
        guard case let .success(localSHA) = local,
              case let .success(branchName) = branch,
              !branchName.isEmpty else {
            return .failure(LocalToolError.updateFailed("No Git branch or repository found."))
        }
        let remote = runCommand(
            executable: "/usr/bin/git",
            arguments: ["-C", directory, "ls-remote", "origin", "refs/heads/\(branchName)"]
        )
        guard case let .success(remoteOutput) = remote,
              let remoteSHA = remoteOutput.split(whereSeparator: \.isWhitespace).first.map(String.init),
              !remoteSHA.isEmpty else {
            return .failure(LocalToolError.updateFailed("No matching origin branch was found."))
        }
        return .success(remoteSHA == localSHA ? "Up to date" : "Update available")
    }
}
