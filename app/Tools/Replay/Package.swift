// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Replay",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../../Packages/EczemaKit")],
    targets: [.executableTarget(name: "Replay", dependencies: [.product(name: "EczemaKit", package: "EczemaKit")])]
)
