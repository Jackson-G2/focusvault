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

    init(definition: LocalToolDefinition) {
        id = definition.id
        self.definition = definition
    }

    var isRunning: Bool {
        state == .runningOwned || state == .runningExternal
    }

    var isOwned: Bool { state == .runningOwned }

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
}

enum LocalToolProcessSupervisor {
    static func run(configurationPath: String) -> Int32 {
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
            try child.run()

            let signalQueue = DispatchQueue(label: "com.jacksongb.vaulty.tool-supervisor-signals")
            let handledSignals = [SIGTERM, SIGINT, SIGHUP]
            let signalSources = handledSignals.map { signalNumber -> DispatchSourceSignal in
                signal(signalNumber, SIG_IGN)
                let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: signalQueue)
                source.setEventHandler {
                    guard child.isRunning else { return }
                    let childPID = child.processIdentifier
                    let childGroup = getpgid(childPID)
                    if childGroup > 0, childGroup != getpgrp() {
                        _ = kill(-childGroup, SIGTERM)
                    } else {
                        child.terminate()
                    }
                }
                source.resume()
                return source
            }

            child.waitUntilExit()
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

    init(
        catalog: LocalToolCatalog = LocalToolCatalog(),
        defaults: [LocalToolDefinition] = LocalToolDefinition.defaults(),
        supervisorExecutableURL: URL? = Bundle.main.executableURL,
        runDirectory: URL? = nil,
        logDirectory: URL? = nil,
        startsStatusTimer: Bool = true,
        opensWhenReady: Bool = true,
        openURL: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) }
    ) {
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

        runtime.state = .checking
        runtime.statusText = "Checking local ports…"
        runtime.errorText = nil
        probePorts(runtime.definition.expectedPorts) { [weak self, weak runtime] states in
            guard let self, let runtime else { return }
            let openPorts = states.filter(\.value).map(\.key).sorted()
            if let primary = runtime.definition.primaryPort, states[primary] == true {
                runtime.state = .runningExternal
                runtime.statusText = "Running externally"
                self.openPrimaryLink(runtime)
                return
            }
            if !openPorts.isEmpty, !runtime.definition.allowsPartialReuse {
                self.fail(runtime, LocalToolError.partiallyRunning(openPorts))
                return
            }
            do {
                try self.launch(runtime)
            } catch {
                self.fail(runtime, error)
            }
        }
    }

    func stop(_ runtime: LocalToolRuntime) {
        guard runtime.state == .runningOwned,
              let pid = runtime.supervisorPID,
              isVerifiedSupervisor(pid: pid) else {
            runtime.errorText = "Vaulty can stop only verified process groups it started."
            return
        }
        guard getpgid(pid) == pid else {
            fail(runtime, LocalToolError.stopRefused)
            return
        }

        runtime.state = .stopping
        runtime.statusText = "Stopping owned process…"
        runtime.errorText = nil
        guard kill(-pid, SIGTERM) == 0 else {
            fail(runtime, LocalToolError.stopRefused)
            return
        }
        scheduleStopVerification(runtime, attempt: 0)
    }

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

    func refreshStatuses() {
        for runtime in tools where runtime.state != .stopping {
            probePorts(runtime.definition.expectedPorts) { [weak self, weak runtime] states in
                guard let self, let runtime else { return }
                let primaryOpen = runtime.definition.primaryPort.map { states[$0] == true }
                    ?? states.values.contains(true)
                let ownedAlive = runtime.supervisorPID.map { self.isVerifiedSupervisor(pid: $0) } == true
                if ownedAlive {
                    runtime.state = primaryOpen ? .runningOwned : .starting
                    runtime.statusText = primaryOpen ? "Running · started by Vaulty" : "Starting local service…"
                } else if primaryOpen {
                    if runtime.supervisorPID != nil {
                        self.removeRunRecord(for: runtime.id)
                        runtime.supervisorPID = nil
                        runtime.supervisorProcess = nil
                    }
                    runtime.state = .runningExternal
                    runtime.statusText = "Running externally"
                } else if runtime.state != .failed {
                    if runtime.supervisorPID != nil {
                        self.removeRunRecord(for: runtime.id)
                        runtime.supervisorPID = nil
                        runtime.supervisorProcess = nil
                    }
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
                guard runtime.supervisorPID == process.processIdentifier else { return }
                self.removeRunRecord(for: runtime.id)
                runtime.supervisorProcess = nil
                runtime.supervisorPID = nil
                runtime.logHandle = nil
                runtime.readinessWorkItem?.cancel()
                runtime.readinessWorkItem = nil
                if runtime.state != .stopping {
                    runtime.state = process.terminationStatus == 0 ? .stopped : .failed
                    runtime.statusText = process.terminationStatus == 0 ? "Stopped" : "Exited · check the Vaulty tool log"
                }
            }
        }

        runtime.supervisorProcess = process
        runtime.state = .starting
        runtime.statusText = "Starting \(definition.name)…"
        try process.run()
        runtime.supervisorPID = process.processIdentifier
        do {
            try writeRunRecord(
                LocalToolRunRecord(
                    toolID: definition.id,
                    supervisorPID: process.processIdentifier,
                    supervisorExecutablePath: supervisorExecutableURL.path,
                    configurationPath: configURL.path,
                    startedAt: Date()
                )
            )
        } catch {
            process.terminate()
            runtime.supervisorPID = nil
            throw error
        }
        waitForReadiness(runtime, attempt: 0)
    }

    private func waitForReadiness(_ runtime: LocalToolRuntime, attempt: Int) {
        guard runtime.state == .starting else { return }
        let ports = runtime.definition.expectedPorts
        probePorts(ports) { [weak self, weak runtime] states in
            guard let self, let runtime, runtime.state == .starting else { return }
            let ready = runtime.definition.primaryPort.map { states[$0] == true }
                ?? states.values.contains(true)
            if ready {
                runtime.state = .runningOwned
                runtime.statusText = "Running · started by Vaulty"
                if self.opensWhenReady {
                    self.openPrimaryLink(runtime)
                }
                return
            }
            guard runtime.supervisorProcess?.isRunning == true else {
                self.fail(runtime, LocalToolError.launchFailed("The tool exited before its local link became ready."))
                return
            }
            guard attempt < 80 else {
                self.fail(runtime, LocalToolError.launchFailed("The tool did not become ready within 40 seconds. Check its Vaulty log."))
                return
            }
            let work = DispatchWorkItem { [weak self, weak runtime] in
                guard let self, let runtime else { return }
                self.waitForReadiness(runtime, attempt: attempt + 1)
            }
            runtime.readinessWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
        }
    }

    private func scheduleStopVerification(_ runtime: LocalToolRuntime, attempt: Int) {
        probePorts(runtime.definition.expectedPorts) { [weak self, weak runtime] states in
            guard let self, let runtime else { return }
            let primaryOpen = runtime.definition.primaryPort.map { states[$0] == true }
                ?? states.values.contains(true)
            if !primaryOpen {
                self.removeRunRecord(for: runtime.id)
                runtime.supervisorProcess = nil
                runtime.supervisorPID = nil
                runtime.state = .stopped
                runtime.statusText = "Stopped by Vaulty"
                return
            }
            guard attempt < 20 else {
                runtime.state = .failed
                runtime.statusText = "Stop requested"
                runtime.errorText = "The local port is still open. Vaulty did not force-kill it."
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                self.scheduleStopVerification(runtime, attempt: attempt + 1)
            }
        }
    }

    private func fail(_ runtime: LocalToolRuntime, _ error: Error) {
        if let process = runtime.supervisorProcess, process.isRunning {
            let pid = process.processIdentifier
            if getpgid(pid) == pid {
                _ = kill(-pid, SIGTERM)
            }
        }
        runtime.state = .failed
        runtime.statusText = "Needs attention"
        runtime.errorText = error.localizedDescription
    }

    private func restoreOwnedRuns() {
        for runtime in tools {
            guard let record = readRunRecord(for: runtime.id) else { continue }
            guard record.toolID == runtime.id,
                  record.configurationPath.hasPrefix(runDirectory.path + "/"),
                  isVerifiedSupervisor(pid: record.supervisorPID) else {
                removeRunRecord(for: runtime.id)
                continue
            }
            runtime.supervisorPID = record.supervisorPID
            runtime.state = .starting
            runtime.statusText = "Reconnecting to Vaulty-owned process…"
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

        var expectedPaths = Set<String>()
        if let supervisorExecutableURL {
            expectedPaths.insert(supervisorExecutableURL.standardizedFileURL.resolvingSymlinksInPath().path)
        }
        for runtime in tools {
            if let record = readRunRecord(for: runtime.id), record.supervisorPID == pid {
                expectedPaths.insert(
                    URL(fileURLWithPath: record.supervisorExecutablePath)
                        .standardizedFileURL
                        .resolvingSymlinksInPath()
                        .path
                )
            }
        }
        guard !expectedPaths.isEmpty else { return false }

        var buffer = [CChar](repeating: 0, count: 4_096)
        let count = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard count > 0 else { return false }
        let actualPath = URL(fileURLWithPath: String(cString: buffer))
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path
        return expectedPaths.contains(actualPath)
    }

    private func persist() throws {
        try catalog.save(tools.map(\.definition))
    }

    private func probePorts(
        _ ports: [Int],
        completion: @escaping ([Int: Bool]) -> Void
    ) {
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
