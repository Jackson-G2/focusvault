import Foundation

extension LocalToolsManager {
    func launch(_ runtime: LocalToolRuntime) throws {
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
            environmentPath: LocalToolCommandRunner.searchPath
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
                guard runtime.supervisorProcess === process,
                      runtime.supervisorPID == process.processIdentifier,
                      runtime.generation == generation, runtime.state != .stopping else { return }
                self.beginOperation(runtime)
                runtime.state = process.terminationStatus == 0 ? .stopped : .failed
                runtime.statusText = process.terminationStatus == 0 ? "Stopped" : "Exited · check the Vaulty tool log"
                self.refreshStatus(runtime) // Clear ownership only after observed port closure.
            }
        }

        runtime.supervisorProcess = process
        runtime.state = .starting
        runtime.statusText = "Starting \(definition.name)…"
        do {
            try process.run()
        } catch {
            runtime.supervisorProcess = nil
            throw error
        }
        runtime.supervisorPID = process.processIdentifier
        let identity = LocalToolProcessIdentity.info(process.processIdentifier)
        let record = LocalToolRunRecord(
            toolID: definition.id,
            supervisorPID: process.processIdentifier,
            supervisorExecutablePath: supervisorExecutableURL.path,
            configurationPath: configURL.path,
            startedAt: Date(),
            reusedPorts: Array(runtime.reusedPorts).sorted(),
            startSeconds: identity?.pbi_start_tvsec,
            startMicroseconds: identity?.pbi_start_tvusec
        )
        runtime.unsavedRunRecord = record
        do {
            try writeRunRecord(record)
            runtime.unsavedRunRecord = nil
        } catch {
            process.terminate()
            // Retain in-memory ownership even if persistence failed.
            throw error
        }
        waitForReadiness(runtime, generation: generation, attempt: 0)
    }
}
