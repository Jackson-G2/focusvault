import Darwin
import Foundation

/// Bounded, non-interactive commands. Call on a utility queue, never the UI queue.
/// Drains both streams while the child runs, without waiting for EOF from a
/// descendant that inherits a writer. It signals only the child it owns.
enum LocalToolCommandRunner {
    // A timed-out CLI can ignore SIGTERM. Keep its exact Process retained until
    // Foundation confirms exit, and escalate only that owned child (not a group
    // or service listener). Reaping stays off the caller's/UI thread.
    private static let ownershipLock = NSLock()
    private static var ownedCommands: [UUID: Process] = [:]

    private static func release(_ id: UUID) {
        ownershipLock.lock()
        ownedCommands.removeValue(forKey: id)
        ownershipLock.unlock()
    }

    struct Output {
        let status: Int32?
        let exitedNormally: Bool
        let timedOut: Bool
        let standardOutput: String
        let standardError: String
        let text: String
    }

    static var searchPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            "/opt/homebrew/bin", "/usr/local/bin",
            home.appendingPathComponent(".local/bin").path,
            home.appendingPathComponent(".npm-global/bin").path,
            "/usr/bin", "/bin"
        ].joined(separator: ":")
    }

    static func run(
        executable: String,
        arguments: [String],
        directory: String? = nil,
        environment: [String: String]? = nil,
        timeout: TimeInterval = 15,
        outputLimit: Int = 16_384
    ) throws -> Output {
        let process = Process()
        let pipes = [Pipe(), Pipe()]
        defer {
            for pipe in pipes {
                try? pipe.fileHandleForReading.close()
                try? pipe.fileHandleForWriting.close()
            }
        }
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = pipes[0]
        process.standardError = pipes[1]
        if let directory {
            process.currentDirectoryURL = URL(fileURLWithPath: directory, isDirectory: true)
        }
        var resolvedEnvironment = environment ?? ProcessInfo.processInfo.environment
        if environment == nil { resolvedEnvironment["PATH"] = searchPath }
        process.environment = resolvedEnvironment

        let descriptors = pipes.map { $0.fileHandleForReading.fileDescriptor }
        for descriptor in descriptors {
            let flags = fcntl(descriptor, F_GETFL, 0)
            guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0 else {
                throw LocalToolError.updateFailed("Could not prepare command output capture.")
            }
        }
        let commandID = UUID()
        process.terminationHandler = { _ in release(commandID) }
        ownershipLock.lock()
        ownedCommands[commandID] = process
        ownershipLock.unlock()
        do { try process.run() }
        catch { release(commandID); throw error }
        let identity = LocalToolProcessIdentity.info(process.processIdentifier)
        for pipe in pipes { try? pipe.fileHandleForWriting.close() }

        let limit = max(0, outputLimit)
        var streams = [Data(), Data()]
        var combined = Data()
        var buffer = [UInt8](repeating: 0, count: 8_192)
        let duration = UInt64(max(0, min(timeout.isFinite ? timeout : 15, 86_400)) * 1_000_000_000)
        let started = DispatchTime.now().uptimeNanoseconds
        var eof = [false, false]
        func append(_ data: ArraySlice<UInt8>, to capture: inout Data) {
            guard limit > 0 else { return }
            capture.append(contentsOf: data.suffix(limit))
            if capture.count > limit { capture.removeFirst(capture.count - limit) }
        }
        // Cap each pass, so an endlessly noisy child cannot evade timeout or
        // starve the other stream. Each stream and the combined tail are bounded.
        func drain() {
            for index in descriptors.indices where !eof[index] {
                for _ in 0..<16 {
                    let count = Darwin.read(descriptors[index], &buffer, buffer.count)
                    if count > 0 {
                        append(buffer.prefix(count), to: &streams[index])
                        append(buffer.prefix(count), to: &combined)
                    } else {
                        if count == 0 { eof[index] = true }
                        if count < 0, errno == EINTR { continue }
                        break
                    }
                }
            }
        }
        func output(timedOut: Bool) -> Output {
            func text(_ data: Data) -> String {
                String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return Output(
                status: timedOut ? nil : process.terminationStatus,
                exitedNormally: !timedOut && process.terminationReason == .exit,
                timedOut: timedOut,
                standardOutput: text(streams[0]), standardError: text(streams[1]), text: text(combined)
            )
        }
        while true {
            drain()
            if !process.isRunning {
                // Drain the available tail; never wait for inherited writers.
                drain()
                return output(timedOut: false)
            }
            if DispatchTime.now().uptimeNanoseconds - started >= duration {
                if process.isRunning { process.terminate() }
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.25) {
                    guard process.isRunning, let identity,
                          let current = LocalToolProcessIdentity.info(process.processIdentifier),
                          current.pbi_start_tvsec == identity.pbi_start_tvsec,
                          current.pbi_start_tvusec == identity.pbi_start_tvusec else { return }
                    _ = kill(process.processIdentifier, SIGKILL)
                }
                return output(timedOut: true)
            }
            var readiness = descriptors.enumerated().compactMap { index, descriptor in
                eof[index] ? nil : pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
            }
            if readiness.isEmpty { Thread.sleep(forTimeInterval: 0.025) }
            else { _ = poll(&readiness, nfds_t(readiness.count), 25) }
        }
    }

    static func runForUpdate(
        executable: String,
        arguments: [String],
        directory: String? = nil,
        timeout: TimeInterval = 15
    ) -> Result<String, Error> {
        do {
            let output = try run(executable: executable, arguments: arguments, directory: directory, timeout: timeout)
            guard !output.timedOut else { throw LocalToolError.updateFailed("Update check timed out.") }
            guard output.exitedNormally, output.status == 0 else {
                throw LocalToolError.updateFailed(output.standardError.isEmpty ? "Update check failed." : output.standardError)
            }
            return .success(output.standardOutput)
        } catch {
            return .failure(error)
        }
    }
}
