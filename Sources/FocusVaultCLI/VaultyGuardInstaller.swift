import Darwin
import Foundation
import VaultyCore

private enum VaultyGuardInstallerError: Error, LocalizedError {
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
    static let extensionID = "apgojdoelgpjfpmiohffnbkfcbjhjhob"

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

    static func launchDaemonPropertyListData() throws -> Data {
        let propertyList: [String: Any] = [
            "Label": YouTubeGuardPaths.launchDaemonLabel,
            "ProgramArguments": [
                YouTubeGuardPaths.helperPath,
                "internal-guard-daemon"
            ],
            "RunAtLoad": true,
            "KeepAlive": true,
            "ProcessType": "Background",
            "ThrottleInterval": 2,
            "StandardOutPath": "/dev/null",
            "StandardErrorPath": "/dev/null"
        ]
        return try PropertyListSerialization.data(
            fromPropertyList: propertyList,
            format: .xml,
            options: 0
        )
    }

    static func authorizationRightPropertyListData() throws -> Data {
        let propertyList: [String: Any] = [
            "class": "user",
            "group": "admin",
            "shared": false,
            "timeout": 0,
            "tries": 3,
            "comment": "Authenticate before Vaulty opens YouTube for a timed session."
        ]
        return try PropertyListSerialization.data(
            fromPropertyList: propertyList,
            format: .xml,
            options: 0
        )
    }

    static func nativeHostManifestData() throws -> Data {
        let manifest: [String: Any] = [
            "name": YouTubeGuardPaths.nativeHostName,
            "description": "Read-only Vaulty YouTube lock status bridge",
            "path": YouTubeGuardPaths.nativeHostPath,
            "type": "stdio",
            "allowed_origins": ["chrome-extension://\(extensionID)/"]
        ]
        return try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
    }

    static func verifyRenderedConfiguration() throws {
        let daemon = try PropertyListSerialization.propertyList(
            from: launchDaemonPropertyListData(),
            options: [],
            format: nil
        ) as? [String: Any]
        guard daemon?["Label"] as? String == YouTubeGuardPaths.launchDaemonLabel,
              (daemon?["ProgramArguments"] as? [String]) == [
                YouTubeGuardPaths.helperPath,
                "internal-guard-daemon"
              ],
              daemon?["RunAtLoad"] as? Bool == true,
              daemon?["KeepAlive"] as? Bool == true else {
            throw VaultyGuardInstallerError.commandFailed("The rendered LaunchDaemon configuration is invalid.")
        }

        let right = try PropertyListSerialization.propertyList(
            from: authorizationRightPropertyListData(),
            options: [],
            format: nil
        ) as? [String: Any]
        guard right?["group"] as? String == "admin",
              right?["shared"] as? Bool == false,
              right?["timeout"] as? Int == 0 else {
            throw VaultyGuardInstallerError.commandFailed("The rendered unlock authorization right is invalid.")
        }

        let native = try JSONSerialization.jsonObject(with: nativeHostManifestData()) as? [String: Any]
        guard native?["name"] as? String == YouTubeGuardPaths.nativeHostName,
              native?["path"] as? String == YouTubeGuardPaths.nativeHostPath,
              (native?["allowed_origins"] as? [String]) == [
                "chrome-extension://\(extensionID)/"
              ] else {
            throw VaultyGuardInstallerError.commandFailed("The rendered native-messaging manifest is invalid.")
        }
    }

    private static func installExecutable(from source: URL, to destination: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let temporary = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent).\(UUID().uuidString).tmp")
        try? fileManager.removeItem(at: temporary)
        try fileManager.copyItem(at: source, to: temporary)
        _ = chmod(temporary.path, 0o755)
        _ = chown(temporary.path, 0, 0)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: temporary, to: destination)
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
        let data = try authorizationRightPropertyListData()
        _ = try run(
            executable: "/usr/bin/security",
            arguments: ["authorizationdb", "write", YouTubeGuardPaths.authorizationRight],
            standardInput: data
        )
    }

    private static func installLaunchDaemon() throws {
        let destination = URL(fileURLWithPath: YouTubeGuardPaths.launchDaemonPath)
        try writeRootFile(try launchDaemonPropertyListData(), to: destination, mode: 0o644)

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
        let data = try nativeHostManifestData()
        for directory in nativeMessagingDirectories(userHome: userHome) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            setOwnerRecursivelyForLeaf(directory, uid: uid, gid: gid)
            let manifest = directory.appendingPathComponent("\(YouTubeGuardPaths.nativeHostName).json")
            try data.write(to: manifest, options: .atomic)
            _ = chmod(manifest.path, 0o644)
            _ = chown(manifest.path, uid, gid)
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
        let directory = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporary = directory.appendingPathComponent(".\(destination.lastPathComponent).\(UUID().uuidString).tmp")
        try data.write(to: temporary, options: .atomic)
        _ = chmod(temporary.path, mode)
        _ = chown(temporary.path, 0, 0)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: temporary, to: destination)
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
