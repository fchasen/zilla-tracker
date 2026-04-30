// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Sliver",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "SliverModel", targets: ["SliverModel"])
    ],
    targets: [
        .target(name: "SliverModel"),
        .testTarget(
            name: "SliverModelTests",
            dependencies: ["SliverModel"]
        )
    ]
)
