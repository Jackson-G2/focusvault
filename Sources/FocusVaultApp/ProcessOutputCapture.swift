import Foundation

struct CapturedProcessOutput {
    let stdout: String
    let stderr: String
    let exitStatus: Int32
}

enum ProcessOutputCaptureError: Error, LocalizedError {
    case outputTooLarge

    var errorDescription: String? {
        "The helper returned more output than Vaulty can safely display."
    }
}

/// Run only from a worker queue. Both pipes must be drained while the child is
/// running: waiting for exit first deadlocks once either OS pipe fills.
enum ProcessOutputCapture {
    static func run(
        _ process: Process,
        limit: Int = 8 * 1_024 * 1_024,
        launch: (() throws -> Void)? = nil
    ) throws -> CapturedProcessOutput {
        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error
        defer {
            try? output.fileHandleForReading.close()
            try? error.fileHandleForReading.close()
        }
        if let launch { try launch() } else { try process.run() }
        let stdout = StreamBuffer(limit: max(0, limit))
        let stderr = StreamBuffer(limit: max(0, limit))
        let readers = DispatchGroup()
        for (pipe, buffer) in [(output, stdout), (error, stderr)] {
            readers.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                defer { readers.leave() }
                buffer.drain(pipe.fileHandleForReading)
            }
        }
        process.waitUntilExit()
        readers.wait()
        guard !stdout.overflowed, !stderr.overflowed else {
            throw ProcessOutputCaptureError.outputTooLarge
        }
        return CapturedProcessOutput(
            stdout: stdout.text,
            stderr: stderr.text,
            exitStatus: process.terminationStatus
        )
    }
}

/// One writer per stream. Results are read only after DispatchGroup.wait(),
/// which supplies the synchronization boundary (no concurrent mutable reads).
private final class StreamBuffer: @unchecked Sendable {
    private let limit: Int
    private var data = Data()
    private(set) var overflowed = false

    init(limit: Int) { self.limit = limit }

    var text: String {
        String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func drain(_ handle: FileHandle) {
        while true {
            let chunk = handle.readData(ofLength: 64 * 1_024)
            guard !chunk.isEmpty else { return }
            let capacity = max(0, limit - data.count)
            if chunk.count > capacity { overflowed = true }
            data.append(chunk.prefix(capacity))
            // Keep draining after the limit so a noisy child cannot block exit.
        }
    }
}
