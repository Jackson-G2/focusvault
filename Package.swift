// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FocusVault",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "FocusVaultCore",
            targets: ["FocusVaultCore"]
        ),
        .executable(
            name: "focusvault",
            targets: ["FocusVaultCLI"]
        ),
        .executable(
            name: "focusvault-self-test",
            targets: ["FocusVaultSelfTest"]
        ),
        .executable(
            name: "focusvault-app",
            targets: ["FocusVaultApp"]
        )
    ],
    targets: [
        .target(
            name: "FocusVaultCore"
        ),
        .executableTarget(
            name: "FocusVaultCLI",
            dependencies: ["FocusVaultCore"]
        ),
        .executableTarget(
            name: "FocusVaultSelfTest",
            dependencies: ["FocusVaultCore"]
        ),
        .executableTarget(
            name: "FocusVaultApp",
            dependencies: ["FocusVaultCore"]
        )
    ]
)
