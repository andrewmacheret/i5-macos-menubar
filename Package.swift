// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "i5-macos-menubar",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "I5Express", targets: ["I5Express"]),
        .executable(name: "i5", targets: ["i5"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.4"),
    ],
    targets: [
        .target(name: "I5Core"),
        .executableTarget(name: "I5Express", dependencies: ["I5Core", .product(name: "Sparkle", package: "Sparkle")]),
        .executableTarget(name: "i5", dependencies: ["I5Core"]),
        .testTarget(
            name: "I5CoreTests",
            dependencies: ["I5Core"],
            resources: [.copy("Fixtures")]
        ),
    ],
    swiftLanguageModes: [.v5]
)
