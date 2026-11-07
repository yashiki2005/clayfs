// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClayFS",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "ClayFSCore",
            targets: ["ClayFSCore"]
        ),
        .executable(
            name: "clayfs",
            targets: ["ClayFSCLI"]
        ),
        .executable(
            name: "ClayFSApp",
            targets: ["ClayFSApp"]
        )
    ],
    targets: [
        .target(
            name: "ClayFSCore",
            dependencies: [],
            path: "Sources/ClayFSCore"
        ),
        .executableTarget(
            name: "ClayFSCLI",
            dependencies: ["ClayFSCore"],
            path: "Sources/ClayFSCLI"
        ),
        .executableTarget(
            name: "ClayFSApp",
            dependencies: ["ClayFSCore"],
            path: "Sources/ClayFSApp",
            exclude: ["Info.plist", "Resources"]
        ),
        .testTarget(
            name: "ClayFSCoreTests",
            dependencies: ["ClayFSCore"],
            path: "Tests/ClayFSCoreTests"
        )
    ]
)
