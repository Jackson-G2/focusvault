import Foundation
import VaultyCore

enum VaultyGuardConfiguration {
    static let extensionID = "apgojdoelgpjfpmiohffnbkfcbjhjhob"

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

}
