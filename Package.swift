// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "LoopBar",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "LoopBar", targets: ["LoopBar"])],
    targets: [.executableTarget(
        name: "LoopBar",
        path: "Sources",
        resources: [.process("Resources")]
    )]
)
