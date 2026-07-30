// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ParkingKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "ParkingKit", targets: ["ParkingKit"]),
        .executable(name: "parkingctl", targets: ["parkingctl"])
    ],
    targets: [
        .target(
            name: "ParkingKit",
            resources: [.process("Resources/facilities.json")]
        ),
        .executableTarget(name: "parkingctl", dependencies: ["ParkingKit"]),
        .testTarget(
            name: "ParkingKitTests",
            dependencies: ["ParkingKit"],
            resources: [.process("Fixtures")]
        )
    ]
)
