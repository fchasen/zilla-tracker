// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "PhabricatorKit",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "PhabricatorKit", targets: ["PhabricatorKit"])
    ],
    targets: [
        .target(name: "PhabricatorKit"),
        .testTarget(
            name: "PhabricatorKitTests",
            dependencies: ["PhabricatorKit"]
        )
    ]
)
