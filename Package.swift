// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Alice",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "AliceCore", targets: ["AliceCore"]),
        .executable(name: "AliceMac", targets: ["AliceMac"])
    ],
    targets: [
        .target(
            name: "AliceCore"
        ),
        .executableTarget(
            name: "AliceMac",
            dependencies: ["AliceCore"]
        ),
        .testTarget(
            name: "AliceCoreTests",
            dependencies: ["AliceCore"]
        )
    ]
)
