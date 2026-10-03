import AppKit
import Combine
import Foundation

/// Main-queue UI facade. Lifecycle, ownership, status and updates live in
/// same-target extensions; only their shared immutable dependencies are internal.
final class LocalToolsManager: ObservableObject {
    let caffeinate = CaffeinateController()
    @Published private(set) var tools: [LocalToolRuntime]
    @Published var isPresentingManager = false
    @Published var isPresentingAddTool = false
    @Published private(set) var catalogError: String?

    private let catalog: LocalToolCatalog
    let supervisorExecutableURL: URL?
    let runDirectory: URL
    let logDirectory: URL
    private let openURL: (URL) -> Bool
    let opensWhenReady: Bool
    private var statusTimer: Timer?
    private let portProbe: (([Int], @escaping ([Int: Bool]) -> Void) -> Void)?
    let externalBBStop: (LocalToolDefinition) throws -> Void

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
        try saveCatalog(tools.map(\.definition) + [validated])
        tools.append(LocalToolRuntime(definition: validated))
        refreshStatuses()
    }

    func remove(_ runtime: LocalToolRuntime) throws {
        guard contains(runtime) else { return }
        guard !runtime.isOwned,
              runtime.state != .checking,
              runtime.state != .starting,
              runtime.state != .stopping else {
            throw LocalToolError.invalidDefinition("Stop this Vaulty-owned process before removing the tool.")
        }
        let remaining = tools.filter { $0 !== runtime }
        try saveCatalog(remaining.map(\.definition))
        beginOperation(runtime) // Invalidate callbacks holding a removed runtime.
        tools = remaining
        removeRunRecord(for: runtime.id)
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

    func contains(_ runtime: LocalToolRuntime) -> Bool {
        tools.contains { $0 === runtime }
    }

    private func saveCatalog(_ definitions: [LocalToolDefinition]) throws {
        do {
            try catalog.save(definitions)
            catalogError = nil
        } catch {
            catalogError = error.localizedDescription
            throw error
        }
    }

    func probePorts(
        _ ports: [Int],
        completion: @escaping ([Int: Bool]) -> Void
    ) {
        // Injected probes may complete off-main. Keep missing ports unknown;
        // lifecycle checks require explicit closure, never an incomplete map.
        let expectedPorts = Set(ports)
        let deliver: ([Int: Bool]) -> Void = { states in
            let resolved = states.filter { expectedPorts.contains($0.key) }
            if Thread.isMainThread { completion(resolved) }
            else { DispatchQueue.main.async { completion(resolved) } }
        }
        if let portProbe { portProbe(ports, deliver); return }
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
            deliver(resolved)
        }
    }
}
