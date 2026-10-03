import Darwin
import Foundation
import VaultyCore

enum VaultyGuardInstallerError: Error, LocalizedError {
    case rootRequired
    case invalidHomeDirectory
    case helperSourceMissing
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .rootRequired:
            return "Administrator permission is required for the one-time Vaulty guard setup."
        case .invalidHomeDirectory:
            return "Vaulty refused an invalid user home directory."
        case .helperSourceMissing:
            return "The bundled Vaulty guard helper could not be found."
        case let .commandFailed(message):
            return message
        }
    }
}

enum VaultyGuardInstaller {
    static func install(userHome: URL, uid: uid_t, gid: gid_t) throws {
        guard geteuid() == 0 else { throw VaultyGuardInstallerError.rootRequired }
        let home = userHome.standardizedFileURL.resolvingSymlinksInPath()
        guard home.path.hasPrefix("/Users/"), home.pathComponents.count >= 3 else {
            throw VaultyGuardInstallerError.invalidHomeDirectory
        }

        let source = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        guard FileManager.default.isExecutableFile(atPath: source.path) else {
            throw VaultyGuardInstallerError.helperSourceMissing
        }

        try installExecutable(from: source, to: URL(fileURLWithPath: YouTubeGuardPaths.helperPath))
        try installExecutable(from: source, to: URL(fileURLWithPath: YouTubeGuardPaths.nativeHostPath))
        try prepareGuardDirectories()
        try installAuthorizationRight()
        try installNativeMessagingManifests(userHome: home, uid: uid, gid: gid)
        try installLaunchDaemon()
    }

    static func installIfNeeded(userHome: URL, uid: uid_t, gid: gid_t) throws {
        guard geteuid() == 0 else { throw VaultyGuardInstallerError.rootRequired }
        let source = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        let destination = URL(fileURLWithPath: YouTubeGuardPaths.helperPath)
        let sourceData = try? Data(contentsOf: source)
        let installedData = try? Data(contentsOf: destination)
        if sourceData == nil || installedData == nil || sourceData != installedData {
            try install(userHome: userHome, uid: uid, gid: gid)
        }
    }

    static func uninstall(userHome: URL) throws {
        guard geteuid() == 0 else { throw VaultyGuardInstallerError.rootRequired }

        _ = try? run(
            executable: "/bin/launchctl",
            arguments: ["bootout", "system/\(YouTubeGuardPaths.launchDaemonLabel)"]
        )

        let blocker = try FocusVaultBlocker()
        _ = try blocker.unblock()

        let paths = [
            YouTubeGuardPaths.launchDaemonPath,
            YouTubeGuardPaths.helperPath,
            YouTubeGuardPaths.nativeHostPath
        ]
        for path in paths {
            try? FileManager.default.removeItem(atPath: path)
        }

        for directory in nativeMessagingDirectories(userHome: userHome) {
            let manifest = directory.appendingPathComponent("\(YouTubeGuardPaths.nativeHostName).json")
            try? FileManager.default.removeItem(at: manifest)
        }

        _ = try? run(
            executable: "/usr/bin/security",
            arguments: ["authorizationdb", "remove", YouTubeGuardPaths.authorizationRight]
        )
        try? FileManager.default.removeItem(atPath: YouTubeGuardPaths.supportDirectory)
    }

    private static func installExecutable(from source: URL, to destination: URL) throws {
        try CLIAtomicFileWriter.write(try Data(contentsOf: source), to: destination, mode: 0o755, owner: 0, group: 0)
    }

    private static func prepareGuardDirectories() throws {
        let fileManager = FileManager.default
        let modes: [(String, mode_t)] = [
            (YouTubeGuardPaths.supportDirectory, 0o755),
            (YouTubeGuardPaths.requestDirectory, 0o1733),
            (YouTubeGuardPaths.responseDirectory, 0o755)
        ]
        for (path, mode) in modes {
            try fileManager.createDirectory(
                at: URL(fileURLWithPath: path, isDirectory: true),
                withIntermediateDirectories: true
            )
            _ = chmod(path, mode)
            _ = chown(path, 0, 0)
        }

        let storage = YouTubeGuardStorage()
        if !fileManager.fileExists(atPath: YouTubeGuardPaths.statePath) {
            try storage.writeState(YouTubeGuardState())
            _ = chmod(YouTubeGuardPaths.statePath, 0o644)
            _ = chown(YouTubeGuardPaths.statePath, 0, 0)
        }
    }

    private static func installAuthorizationRight() throws {
        let data = try VaultyGuardConfiguration.authorizationRightPropertyListData()
        _ = try run(
            executable: "/usr/bin/security",
            arguments: ["authorizationdb", "write", YouTubeGuardPaths.authorizationRight],
            standardInput: data
        )
    }

    private static func installLaunchDaemon() throws {
        let destination = URL(fileURLWithPath: YouTubeGuardPaths.launchDaemonPath)
        try writeRootFile(try VaultyGuardConfiguration.launchDaemonPropertyListData(), to: destination, mode: 0o644)

        _ = try? run(
            executable: "/bin/launchctl",
            arguments: ["bootout", "system/\(YouTubeGuardPaths.launchDaemonLabel)"]
        )
        _ = try run(
            executable: "/bin/launchctl",
            arguments: ["bootstrap", "system", destination.path]
        )
        _ = try? run(
            executable: "/bin/launchctl",
            arguments: ["enable", "system/\(YouTubeGuardPaths.launchDaemonLabel)"]
        )
    }

    private static func installNativeMessagingManifests(
        userHome: URL,
        uid: uid_t,
        gid: gid_t
    ) throws {
        let data = try VaultyGuardConfiguration.nativeHostManifestData()
        for directory in nativeMessagingDirectories(userHome: userHome) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            setOwnerRecursivelyForLeaf(directory, uid: uid, gid: gid)
            let manifest = directory.appendingPathComponent("\(YouTubeGuardPaths.nativeHostName).json")
            try CLIAtomicFileWriter.write(data, to: manifest, mode: 0o644, owner: uid, group: gid)
        }
    }

    private static func nativeMessagingDirectories(userHome: URL) -> [URL] {
        [
            "Library/Application Support/Google/Chrome/NativeMessagingHosts",
            "Library/Application Support/BraveSoftware/Brave-Browser/NativeMessagingHosts",
            "Library/Application Support/Microsoft Edge/NativeMessagingHosts"
        ].map { userHome.appendingPathComponent($0, isDirectory: true) }
    }

    private static func setOwnerRecursivelyForLeaf(_ directory: URL, uid: uid_t, gid: gid_t) {
        _ = chmod(directory.path, 0o755)
        _ = chown(directory.path, uid, gid)
    }

    private static func writeRootFile(_ data: Data, to destination: URL, mode: mode_t) throws {
        try CLIAtomicFileWriter.write(data, to: destination, mode: mode, owner: 0, group: 0)
    }

    @discardableResult
    private static func run(
        executable: String,
        arguments: [String],
        standardInput: Data? = nil
    ) throws -> String {
        let process = Process()
        let output = Pipe()
        let error = Pipe()
        let input = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = error
        if standardInput != nil {
            process.standardInput = input
        }
        try process.run()
        if let standardInput {
            input.fileHandleForWriting.write(standardInput)
            try? input.fileHandleForWriting.close()
        }
        process.waitUntilExit()

        let stdout = String(
            data: output.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let stderr = String(
            data: error.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard process.terminationStatus == 0 else {
            let detail = stderr.isEmpty ? stdout : stderr
            throw VaultyGuardInstallerError.commandFailed(
                detail.isEmpty ? "\(executable) failed with status \(process.terminationStatus)." : detail
            )
        }
        return stdout
    }
}
