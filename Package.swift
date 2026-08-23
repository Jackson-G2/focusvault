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
        )
    ]
)
