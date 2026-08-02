// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Cull",
    platforms: [.macOS(.v15)],
    targets: [
        .target(name: "CullCore"),
        .executableTarget(
            name: "Cull",
            dependencies: ["CullCore"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(name: "CullCoreTests", dependencies: ["CullCore"]),
    ]
)
