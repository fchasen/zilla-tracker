// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "BugzillaKit",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "BugzillaKit", targets: ["BugzillaKit"])
    ],
    targets: [
        .target(name: "BugzillaKit"),
        .testTarget(
            name: "BugzillaKitTests",
            dependencies: ["BugzillaKit"]
        )
    ]
)
