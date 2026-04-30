// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Sliver",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "SliverModel", targets: ["SliverModel"]),
        .library(name: "SliverHighlight", targets: ["SliverHighlight"])
    ],
    targets: [
        .target(name: "SliverModel"),
        .target(name: "SliverHighlight"),
        .testTarget(
            name: "SliverModelTests",
            dependencies: ["SliverModel"]
        ),
        .testTarget(
            name: "SliverHighlightTests",
            dependencies: ["SliverHighlight"]
        )
    ]
)
