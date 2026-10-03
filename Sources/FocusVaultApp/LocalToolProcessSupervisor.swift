import Darwin
import Foundation

struct LocalToolSupervisorConfiguration: Codable {
    let executablePath: String
    let arguments: [String]
    let workingDirectory: String
    let logPath: String
    let environmentPath: String
}

enum LocalToolProcessSupervisor {
    static func run(configurationPath: String) -> Int32 {
        let handledSignals = [SIGTERM, SIGINT, SIGHUP]
        handledSignals.forEach { signal($0, SIG_IGN) }
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
            // Dispositions were installed before establishing the group, so an
            // immediate Cancel cannot bypass descendant bookkeeping.
            try child.run()
            let childGroup = getpgid(child.processIdentifier)
            if childGroup > 1, childGroup != getpgrp() {
                do {
                    try String(childGroup).write(toFile: configurationPath + ".child-pgid", atomically: true, encoding: .utf8)
                } catch {
                    // A failed bookkeeping write must not orphan a launched
                    // child. This supervisor still retains the exact group and
                    // remains alive until it drains, including on Cancel/Stop.
                    log.write(Data("Vaulty could not persist child-group metadata; supervisor ownership retained.\n".utf8))
                }
            }

            let signalQueue = DispatchQueue(label: "com.jacksongb.vaulty.tool-supervisor-signals")
            let signalSources = handledSignals.map { signalNumber -> DispatchSourceSignal in
                signal(signalNumber, SIG_IGN)
                let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: signalQueue)
                source.setEventHandler {
                    if childGroup > 1, childGroup != getpgrp() {
                        _ = kill(-childGroup, SIGTERM)
                    } else if child.isRunning {
                        child.terminate()
                    }
                }
                source.resume()
                return source
            }

            // Keep ownership alive until the isolated child group has drained,
            // including descendants that outlive the command's immediate child.
            child.waitUntilExit()
            if childGroup > 1, childGroup != getpgrp() {
                while kill(-childGroup, 0) == 0 || errno == EPERM {
                    Thread.sleep(forTimeInterval: 0.1)
                }
            }
            signalSources.forEach { $0.cancel() }
            return child.terminationStatus
        } catch {
            let message = "Vaulty tool supervisor failed: \(error.localizedDescription)\n"
            FileHandle.standardError.write(Data(message.utf8))
            return 1
        }
    }
}
