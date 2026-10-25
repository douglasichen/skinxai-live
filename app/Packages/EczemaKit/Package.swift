// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "EczemaKit",
    platforms: [.iOS(.v17), .watchOS(.v10), .macOS(.v14)],
    products: [.library(name: "EczemaKit", targets: ["EczemaKit"])],
    targets: [
        .target(name: "EczemaKit", resources: [.process("Resources")]),
        .testTarget(name: "EczemaKitTests", dependencies: ["EczemaKit"]),
    ]
)
