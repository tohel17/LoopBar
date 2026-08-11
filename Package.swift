// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "LoopBar",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "LoopBar", targets: ["LoopBar"])],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.5")
    ],
    targets: [
        .executableTarget(
            name: "LoopBar",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources",
            resources: [
                .copy("Resources/version.txt"),
                .copy("Resources/NotificationLogo.png")
            ]
        ),
        .testTarget(name: "LoopBarTests", dependencies: ["LoopBar"])
    ]
)
