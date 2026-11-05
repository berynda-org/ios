// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BeryndaCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "BeryndaCore", targets: ["BeryndaCore"]),
    ],
    targets: [
        .target(
            name: "BeryndaCore",
            linkerSettings: [.linkedFramework("Security")]
        ),
        .testTarget(
            name: "BeryndaCoreTests",
            dependencies: ["BeryndaCore"],
            resources: [.process("Fixtures")]
        ),
    ]
)
