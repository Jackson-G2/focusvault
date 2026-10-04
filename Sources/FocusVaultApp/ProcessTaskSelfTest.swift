import Foundation

enum ProcessTaskSelfTest {
    static func run() throws {
        let unstarted = Process()
        unstarted.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        let cancelled = CapturedProcessTask(unstarted)
        cancelled.cancel()
        do {
            _ = try cancelled.run()
            throw Failure.invalid("cancelled job launched")
        } catch is CancellationError {
            guard !unstarted.isRunning else { throw Failure.invalid("cancelled helper is running") }
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-c", "import time; time.sleep(60)"]
        let task = CapturedProcessTask(process)
        let completed = DispatchGroup()
        let probe = CompletionProbe()
        completed.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            probe.result = Result { try task.run() }
            completed.leave()
        }
        let deadline = Date().addingTimeInterval(5)
        while !process.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
        task.cancel()
        guard completed.wait(timeout: .now() + 5) == .success, !process.isRunning else {
            throw Failure.invalid("owned helper did not finish after cancel")
        }
        guard case .success = probe.result else { throw Failure.invalid("cancelled running helper was not drained") }
        do {
            _ = try task.run()
            throw Failure.invalid("one-shot process task ran twice")
        } catch is Failure {
            throw Failure.invalid("one-shot process task ran twice")
        } catch {
            // Rejection happens before reconfiguring pipes or Process.run.
        }
        print("PASS: helper cancellation before/during launch and one-shot execution; owned child drained and exited")
    }

    // Read only after DispatchGroup.wait(), matching the capture synchronization boundary.
    private final class CompletionProbe: @unchecked Sendable {
        var result: Result<CapturedProcessOutput, Error>?
    }
    private enum Failure: Error { case invalid(String) }
}
