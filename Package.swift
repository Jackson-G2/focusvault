// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Vaulty",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "VaultyCore",
            targets: ["VaultyCore"]
        ),
        .executable(
            name: "vaulty",
            targets: ["VaultyCLI"]
        ),
        .executable(
            name: "vaulty-self-test",
            targets: ["VaultySelfTest"]
        ),
        .executable(
            name: "vaulty-app",
            targets: ["VaultyApp"]
        ),
        // Compatibility products retained for existing FocusVault installs/scripts.
        .executable(
            name: "focusvault",
            targets: ["VaultyCLI"]
        ),
        .executable(
            name: "focusvault-self-test",
            targets: ["VaultySelfTest"]
        ),
        .executable(
            name: "focusvault-app",
            targets: ["VaultyApp"]
        )
    ],
    targets: [
        .target(
            name: "VaultyCore",
            path: "Sources/FocusVaultCore"
        ),
        .executableTarget(
            name: "VaultyCLI",
            dependencies: ["VaultyCore"],
            path: "Sources/FocusVaultCLI"
        ),
        .executableTarget(
            name: "VaultySelfTest",
            dependencies: ["VaultyCore"],
            path: "Sources/FocusVaultSelfTest"
        ),
        .executableTarget(
            name: "VaultyApp",
            dependencies: ["VaultyCore"],
            path: "Sources/FocusVaultApp"
        )
    ]
)
