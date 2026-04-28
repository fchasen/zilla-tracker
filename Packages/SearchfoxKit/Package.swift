// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.
// Swift Package: SearchfoxKit

import PackageDescription;

let package = Package(
    name: "SearchfoxKit",
    platforms: [
        .macOS(.v10_15), .iOS(.v13), .visionOS(.v1)
    ],
    products: [
        .library(
            name: "SearchfoxKit",
            targets: ["SearchfoxKit"]
        )
    ],
    dependencies: [ ],
    targets: [
        .binaryTarget(name: "searchfox_bridgeFFI", path: "./searchfox_bridgeFFI.xcframework"),
        .target(
            name: "SearchfoxKit",
            dependencies: [
                .target(name: "searchfox_bridgeFFI")
            ]
        ),
    ]
)