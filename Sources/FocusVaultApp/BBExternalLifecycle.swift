import Foundation

/// Narrow exception to external-process protection, exclusively for the default bb tool.
/// Call `stop(definition:)` on a utility queue AFTER explicit user confirmation:
/// stopping bb interrupts running threads, terminals, and agent work. Never use this
/// helper for a generic external tool. Only bb's official CLI verifies/signals its
/// launcher; this helper never interprets a runtime PID as permission to kill it.
enum BBExternalLifecycle {
    private static let defaultID = UUID(uuidString: "BBA00000-0000-4000-8000-000000000001")!
    private static let port = 38_886
    private static let defaultArguments = [
        "npx", "--yes", "--allow-scripts=better-sqlite3,node-pty,@parcel/watcher", "bb-app@latest"
    ]

    enum Failure: Error, LocalizedError {
        case unsupportedDefinition
        case runtimeUnavailable
        case runtimeMismatch
        case cliUnavailable
        case launchFailed
        case timedOut(String)
        case stopFailed(Int32, String)

        var errorDescription: String? {
            switch self {
            case .unsupportedDefinition:
                return "External stop is available only for the unchanged default bb launcher on loopback port 38886."
            case .runtimeUnavailable:
                return "bb's default runtime record (~/.bb/bb-app-runtime.json) is missing, unreadable, or invalid. Stop bb from the terminal that started it instead."
            case .runtimeMismatch:
                return "bb's runtime record does not describe the default loopback server on port 38886. No stop command was run."
            case .cliUnavailable:
                return "npx is not installed on the supported PATH. Install Node.js/npm, or stop bb from its original terminal. Vaulty will not download a stop tool."
            case .launchFailed:
                return "The local bb stop command could not be launched. Check your Node.js/npm installation; no package downloads are permitted."
            case let .timedOut(log):
                return "The bb stop command timed out after 15 seconds. Check bb's state before retrying; it may already be stopping.\(Self.logSuffix(log))"
            case let .stopFailed(status, log):
                return "The local bb stop command failed (exit \(status)). A locally installed or cached bb-app CLI supporting 'stop' is required; downloads and install prompts are disabled. Stop bb from its original terminal if unavailable.\(Self.logSuffix(log))"
            }
        }

        private static func logSuffix(_ log: String) -> String {
            log.isEmpty ? "" : "\n\nCLI output (bounded):\n\(log)"
        }
    }

    /// Intentionally exact command allowlist: no custom flags, data directories,
    /// env assignments, scripts, package aliases, or alternate launchers qualify.
    /// Installed executable variants are not accepted without a separate audited rule.
    static func matches(_ definition: LocalToolDefinition) -> Bool {
        definition.id == defaultID
            && definition.expectedPorts == [port]
            && definition.primaryPort == port
            && definition.executablePath == "/usr/bin/env"
            && definition.workingDirectory == FileManager.default.homeDirectoryForCurrentUser.path
            && definition.arguments == defaultArguments
            && definition.primaryURL.map(isDefaultLoopbackURL) == true
    }

    /// Synchronous and throwing; returns at most 16 KiB of combined stdout/stderr.
    /// Must not be called on the main queue. Success is CLI success, not a promise
    /// that a listener has disappeared: the caller should refresh its normal status.
    @discardableResult
    static func stop(definition: LocalToolDefinition) throws -> String {
        guard matches(definition) else { throw Failure.unsupportedDefinition }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dataDirectory = home.appendingPathComponent(".bb", isDirectory: true)
        try validateRuntime(in: dataDirectory)

        // Do not inherit shell PATH, NODE_OPTIONS, npm settings, or BB_* overrides.
        // Explicit offline + yes=false complement --no-install: missing packages
        // must fail, not fetch/install or prompt. Lifecycle install scripts are off.
        let pathEntries = [
            "/opt/homebrew/bin", "/usr/local/bin",
            home.appendingPathComponent(".local/bin").path,
            home.appendingPathComponent(".npm-global/bin").path,
            "/usr/bin", "/bin", "/usr/sbin", "/sbin"
        ]
        guard pathEntries.contains(where: {
            FileManager.default.isExecutableFile(atPath: $0 + "/npx")
        }) else { throw Failure.cliUnavailable }

        let environment = [
            "HOME": home.path, "PATH": pathEntries.joined(separator: ":"),
            "CI": "1", "NO_COLOR": "1", "TERM": "dumb",
            "npm_config_offline": "true", "npm_config_yes": "false",
            "npm_config_ignore_scripts": "true", "npm_config_audit": "false",
            "npm_config_fund": "false", "npm_config_update_notifier": "false"
        ]
        let output: LocalToolCommandRunner.Output
        do {
            output = try LocalToolCommandRunner.run(
                executable: "/usr/bin/env",
                arguments: ["npx", "--no-install", "bb-app", "stop", "--data-dir", dataDirectory.path],
                directory: home.path, environment: environment
            )
        } catch {
            throw Failure.launchFailed
        }
        guard !output.timedOut else {
            // The runner signals only its CLI wrapper, never bb's runtime PID,
            // process group or port owner. bb may already be stopping gracefully.
            throw Failure.timedOut(output.text)
        }
        guard output.exitedNormally, output.status == 0 else {
            throw Failure.stopFailed(output.status ?? -1, output.text)
        }
        return output.text
    }

    private static func isDefaultLoopbackURL(_ url: URL) -> Bool {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme == "http", parts.port == port,
              let host = parts.host?.lowercased(),
              ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host),
              parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil,
              parts.path.isEmpty || parts.path == "/" else { return false }
        return true
    }

    // Official schema: packages/config/src/app-runtime-file.ts in get-bb/bb.
    // Decode identity fields without ever logging runtime/config/provider values.
    private struct RuntimeRecord: Decodable {
        let entryPath: String
        let pid: Int
        let surface: String
        let serverUrl: String
        let startedAt: String
        let version: String
    }

    static func validateRuntime(in directory: URL) throws {
        let file = directory.appendingPathComponent("bb-app-runtime.json")
        let record: RuntimeRecord
        do {
            let directoryValues = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            let fileValues = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard directoryValues.isDirectory == true, directoryValues.isSymbolicLink != true,
                  fileValues.isRegularFile == true, fileValues.isSymbolicLink != true else {
                throw Failure.runtimeUnavailable
            }
            let handle = try FileHandle(forReadingFrom: file)
            defer { try? handle.close() }
            let data = try handle.read(upToCount: 65_537) ?? Data()
            guard !data.isEmpty, data.count <= 65_536 else { throw Failure.runtimeUnavailable }
            record = try JSONDecoder().decode(RuntimeRecord.self, from: data)
            guard record.pid > 0, !record.entryPath.isEmpty, !record.surface.isEmpty,
                  !record.startedAt.isEmpty, !record.version.isEmpty else {
                throw Failure.runtimeUnavailable
            }
        } catch {
            throw Failure.runtimeUnavailable
        }
        guard let url = URL(string: record.serverUrl), isDefaultLoopbackURL(url) else {
            throw Failure.runtimeMismatch
        }
        // No PID probing or signaling here. The official stop command rereads the
        // record and verifies the recorded process really is a bb launcher.
    }

}
