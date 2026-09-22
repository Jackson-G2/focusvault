import AppKit
import Combine
import Foundation

enum BBLauncherState: Equatable {
    case idle
    case starting
    case running
    case failed
}

final class BBLauncher: ObservableObject {
    @Published private(set) var state: BBLauncherState = .idle
    @Published private(set) var statusText = "Start the local bb hub."
    @Published private(set) var errorText: String?

    private struct LaunchPlan {
        let executablePath: String
        let arguments: [String]
        let description: String
    }

    private enum BBLauncherError: LocalizedError {
        case launcherMissing

        var errorDescription: String? {
            switch self {
            case .launcherMissing:
                return "No bb desktop app, bb-app command, or npx launcher was found. Install bb or Node.js first."
            }
        }
    }

    private let serverURL = URL(string: "http://127.0.0.1:38886")!
    private var process: Process?
    private var logHandle: FileHandle?
    private var readinessWorkItem: DispatchWorkItem?
    private var desktopAppURL: URL?

    deinit {
        readinessWorkItem?.cancel()
        logHandle?.closeFile()
    }

    var isStarting: Bool {
        state == .starting
    }

    var isRunning: Bool {
        state == .running
    }

    var actionTitle: String {
        switch state {
        case .idle:
            return "Start"
        case .starting:
            return "Starting…"
        case .running:
            return "Open"
        case .failed:
            return "Retry"
        }
    }

    func startOrOpen() {
        guard state != .starting else { return }

        if state == .running {
            openCurrentDestination()
            return
        }

        errorText = nil
        desktopAppURL = nil
        state = .starting
        statusText = "Checking for bb…"

        if let process, process.isRunning {
            statusText = "bb is still starting…"
            waitForServer(attempt: 0)
            return
        }

        probeServer { [weak self] isReady in
            guard let self, self.state == .starting else { return }

            if isReady {
                self.state = .running
                self.statusText = "bb is already running."
                self.openWebUI()
                return
            }

            if let appURL = self.locateDesktopApp() {
                guard NSWorkspace.shared.open(appURL) else {
                    self.fail("Vaulty could not open the bb desktop app.")
                    return
                }
                self.desktopAppURL = appURL
                self.state = .running
                self.statusText = "bb desktop app is open."
                return
            }

            do {
                try self.launch(self.launchPlan())
            } catch {
                self.fail(error.localizedDescription)
            }
        }
    }

    private func launch(_ plan: LaunchPlan) throws {
        let process = Process()
        let log = try makeLogHandle()
        let home = FileManager.default.homeDirectoryForCurrentUser

        process.executableURL = URL(fileURLWithPath: plan.executablePath)
        process.arguments = plan.arguments
        process.currentDirectoryURL = home
        process.standardOutput = log
        process.standardError = log

        var environment = ProcessInfo.processInfo.environment
        let searchPath = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            home.appendingPathComponent(".local/bin").path,
            home.appendingPathComponent(".npm-global/bin").path,
            "/usr/bin",
            "/bin"
        ]
        environment["PATH"] = searchPath.joined(separator: ":")
        process.environment = environment

        process.terminationHandler = { [weak self] terminatedProcess in
            DispatchQueue.main.async {
                self?.handleTermination(terminatedProcess)
            }
        }

        self.logHandle = log
        self.process = process
        try process.run()

        statusText = "Starting \(plan.description)…"
        waitForServer(attempt: 0)
    }

    private func waitForServer(attempt: Int) {
        guard state == .starting else { return }

        probeServer { [weak self] isReady in
            guard let self, self.state == .starting else { return }

            if isReady {
                self.readinessWorkItem?.cancel()
                self.readinessWorkItem = nil
                self.state = .running
                self.statusText = "bb is ready."
                self.openWebUI()
                return
            }

            guard self.process?.isRunning == true else {
                self.fail("bb exited before its local UI became ready. Check the launch log at ~/Library/Logs/Vaulty/bb.log.")
                return
            }

            guard attempt < 40 else {
                self.fail("bb is taking too long to start. Check ~/Library/Logs/Vaulty/bb.log, then try again.")
                return
            }

            let workItem = DispatchWorkItem { [weak self] in
                self?.waitForServer(attempt: attempt + 1)
            }
            self.readinessWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
        }
    }

    private func probeServer(completion: @escaping (Bool) -> Void) {
        var request = URLRequest(url: serverURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 1.0

        URLSession.shared.dataTask(with: request) { _, response, _ in
            DispatchQueue.main.async {
                completion(response != nil)
            }
        }.resume()
    }

    private func openCurrentDestination() {
        if let desktopAppURL {
            _ = NSWorkspace.shared.open(desktopAppURL)
        } else {
            openWebUI()
        }
    }

    private func openWebUI() {
        guard NSWorkspace.shared.open(serverURL) else {
            errorText = "bb is running at http://127.0.0.1:38886, but Vaulty could not open it."
            return
        }
    }

    private func handleTermination(_ terminatedProcess: Process) {
        guard process?.processIdentifier == terminatedProcess.processIdentifier else { return }
        process = nil
        logHandle?.closeFile()
        logHandle = nil

        guard state == .starting || state == .running else { return }

        if state == .starting {
            fail("bb stopped before its local UI became ready. Check ~/Library/Logs/Vaulty/bb.log.")
        } else {
            state = .idle
            statusText = "bb has stopped."
        }
    }

    private func fail(_ message: String) {
        readinessWorkItem?.cancel()
        readinessWorkItem = nil
        state = .failed
        statusText = "bb needs attention."
        errorText = message
    }

    private func locateDesktopApp() -> URL? {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            home.appendingPathComponent("Applications", isDirectory: true),
            home.appendingPathComponent("Downloads", isDirectory: true)
        ]
        let names = ["bb.app", "BB.app", "bb Desktop.app"]

        for root in roots {
            for name in names {
                let candidate = root.appendingPathComponent(name, isDirectory: true)
                if fileManager.fileExists(atPath: candidate.path) {
                    return candidate
                }
            }
        }
        return nil
    }

    private func launchPlan() throws -> LaunchPlan {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let environmentPaths = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
        let searchPaths = environmentPaths + [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            home.appendingPathComponent(".local/bin").path,
            home.appendingPathComponent(".npm-global/bin").path,
            "/usr/bin",
            "/bin"
        ]

        for directory in searchPaths {
            let candidate = URL(fileURLWithPath: directory).appendingPathComponent("bb-app")
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return LaunchPlan(
                    executablePath: candidate.path,
                    arguments: [],
                    description: "bb"
                )
            }
        }

        for directory in searchPaths {
            let candidate = URL(fileURLWithPath: directory).appendingPathComponent("npx")
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return LaunchPlan(
                    executablePath: candidate.path,
                    arguments: [
                        "--yes",
                        "--allow-scripts=better-sqlite3,node-pty,@parcel/watcher",
                        "bb-app@latest"
                    ],
                    description: "the official npx bb-app launcher"
                )
            }
        }

        throw BBLauncherError.launcherMissing
    }

    private func makeLogHandle() throws -> FileHandle {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let logURL = home
            .appendingPathComponent("Library/Logs", isDirectory: true)
            .appendingPathComponent("Vaulty", isDirectory: true)
            .appendingPathComponent("bb.log")
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: logURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if !fileManager.fileExists(atPath: logURL.path) {
            fileManager.createFile(atPath: logURL.path, contents: Data())
        }
        let handle = try FileHandle(forWritingTo: logURL)
        try handle.seekToEnd()
        return handle
    }
}
