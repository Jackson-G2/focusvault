// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Frostwall",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "FrostwallCore",
            targets: ["FrostwallCore"]
        ),
        .executable(
            name: "frostwall",
            targets: ["FrostwallCLI"]
        ),
        .executable(
            name: "frostwall-self-test",
            targets: ["FrostwallSelfTest"]
        )
    ],
    targets: [
        .target(
            name: "FrostwallCore"
        ),
        .executableTarget(
            name: "FrostwallCLI",
            dependencies: ["FrostwallCore"]
        ),
        .executableTarget(
            name: "FrostwallSelfTest",
            dependencies: ["FrostwallCore"]
        )
    ]
)
