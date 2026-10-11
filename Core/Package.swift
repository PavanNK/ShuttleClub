// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "ShuttleCore",
    platforms: [.macOS(.v14), .visionOS(.v2)],
    products: [.library(name: "ShuttleCore", targets: ["ShuttleCore"])],
    targets: [.target(name: "ShuttleCore"), .testTarget(name: "ShuttleCoreTests", dependencies: ["ShuttleCore"])]
)
