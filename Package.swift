// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "btmicrouter",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "RoutingCore"),
        .executableTarget(
            name: "btmicrouter",
            dependencies: ["RoutingCore"]
        ),
        .testTarget(
            name: "RoutingCoreTests",
            dependencies: ["RoutingCore"]
        ),
    ]
)
