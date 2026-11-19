// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "i5-macos-menubar",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "I5Express", targets: ["I5Express"]),
        .executable(name: "i5", targets: ["i5"]),
    ],
    targets: [
        .target(name: "I5Core"),
        .executableTarget(name: "I5Express", dependencies: ["I5Core"]),
        .executableTarget(name: "i5", dependencies: ["I5Core"]),
        .testTarget(
            name: "I5CoreTests",
            dependencies: ["I5Core"],
            resources: [.copy("Fixtures")]
        ),
    ],
    swiftLanguageModes: [.v5]
)
