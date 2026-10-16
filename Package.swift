// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "LimitNotch",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "LimitNotch", targets: ["LimitNotch"])
    ],
    targets: [
        .target(name: "LimitNotchCore"),
        .executableTarget(name: "LimitNotch", dependencies: ["LimitNotchCore"]),
        .testTarget(name: "LimitNotchCoreTests", dependencies: ["LimitNotchCore"])
    ]
)
