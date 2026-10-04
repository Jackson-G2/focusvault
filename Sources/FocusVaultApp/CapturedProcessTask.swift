import Foundation

/// The model can be released between scheduling background work and Process.run.
/// Serializing launch/cancel prevents launching a helper after its owner is gone,
/// and avoids calling terminate on a Process which has never started.
final class CapturedProcessTask: @unchecked Sendable {
    private let process: Process
    private let lock = NSLock()
    private var cancelled = false
    private var claimed = false
    private var started = false

    init(_ process: Process) { self.process = process }

    func run() throws -> CapturedProcessOutput {
        lock.lock()
        if cancelled {
            lock.unlock()
            throw CancellationError()
        }
        if claimed {
            lock.unlock()
            throw TaskError.alreadyStarted
        }
        claimed = true
        lock.unlock()
        return try ProcessOutputCapture.run(process, launch: start)
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        cancelled = true
        if started, process.isRunning { process.terminate() }
    }

    private func start() throws {
        lock.lock()
        defer { lock.unlock() }
        guard !cancelled else { throw CancellationError() }
        guard !started else { throw TaskError.alreadyStarted }
        try process.run()
        started = true
    }

    private enum TaskError: Error { case alreadyStarted }
}
