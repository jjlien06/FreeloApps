// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SnipText",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0"),
    ],
    targets: [
        .target(name: "SnipTextCore"),
        .executableTarget(
            name: "SnipText",
            dependencies: ["SnipTextCore", "KeyboardShortcuts"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(name: "SnipTextCoreTests", dependencies: ["SnipTextCore"]),
    ]
)
