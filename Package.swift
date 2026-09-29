// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FoldBar",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "FoldBar", targets: ["FoldBar"])],
    targets: [
        .target(name: "FoldBarCore"),
        .executableTarget(name: "FoldBar", dependencies: ["FoldBarCore"]),
        .testTarget(name: "FoldBarCoreTests", dependencies: ["FoldBarCore"])
    ]
)
