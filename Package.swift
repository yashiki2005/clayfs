// swift-tools-version: 6.0
import PackageDescription

var products: [Product] = [
    .library(
        name: "ClayFSCore",
        targets: ["ClayFSCore"]
    ),
    .executable(
        name: "clayfs",
        targets: ["ClayFSCLI"]
    )
]

var targets: [Target] = [
    .systemLibrary(
        name: "CSQLite",
        path: "Sources/CSQLite"
    ),
    .target(
        name: "ClayFSCore",
        dependencies: [
            .target(name: "CSQLite", condition: .when(platforms: [.linux]))
        ],
        path: "Sources/ClayFSCore",
        linkerSettings: [
            .linkedLibrary("sqlite3", .when(platforms: [.linux]))
        ]
    ),
    .executableTarget(
        name: "ClayFSCLI",
        dependencies: ["ClayFSCore"],
        path: "Sources/ClayFSCLI"
    ),
    .testTarget(
        name: "ClayFSCoreTests",
        dependencies: ["ClayFSCore"],
        path: "Tests/ClayFSCoreTests"
    )
]

#if os(macOS)
products.append(
    .executable(
        name: "ClayFSApp",
        targets: ["ClayFSApp"]
    )
)
targets.append(
    .executableTarget(
        name: "ClayFSApp",
        dependencies: ["ClayFSCore"],
        path: "Sources/ClayFSApp",
        exclude: ["Info.plist", "Resources"]
    )
)
#endif

let package = Package(
    name: "ClayFS",
    platforms: [
        .macOS(.v14)
    ],
    products: products,
    targets: targets
)
