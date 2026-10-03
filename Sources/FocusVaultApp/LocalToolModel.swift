import Combine
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
        var isDirectory: ObjCBool = false
        guard !cwd.isEmpty, fileManager.fileExists(atPath: cwd, isDirectory: &isDirectory), isDirectory.boolValue else {
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
        validated.links = links.map { link in
            var cleanLink = link
            cleanLink.name = link.name.trimmingCharacters(in: .whitespacesAndNewlines)
            cleanLink.urlString = link.urlString.trimmingCharacters(in: .whitespacesAndNewlines)
            return cleanLink
        }
        validated.updateIdentifier = updateIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        return validated
    }

    private func expandedPath(_ value: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return value
            .replacingOccurrences(of: "$HOME", with: home)
            .replacingOccurrences(of: "~", with: home, options: [.anchored])
    }

    /// The form must not silently discard a mistyped port with compactMap.
    static func parsePorts(_ text: String) throws -> [Int] {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        return try text.split(separator: ",", omittingEmptySubsequences: false).map { token in
            guard let port = Int(token.trimmingCharacters(in: .whitespacesAndNewlines)),
                  (1...65_535).contains(port) else {
                throw LocalToolError.invalidDefinition("Enter comma-separated ports between 1 and 65535.")
            }
            return port
        }
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

    var supervisorProcess: Process?
    var supervisorPID: pid_t?
    var readinessWorkItem: DispatchWorkItem?
    var generation = UUID()
    var statusGeneration = UUID()
    var pendingStatusProbe: UUID?
    // Only used if saving a newly launched run fails; keeps safe recovery possible.
    var unsavedRunRecord: LocalToolRunRecord?
    var restartPending = false
    var reusedPorts: Set<Int> = []

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
