// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Marginalia",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "MarginaliaSyntax", targets: ["MarginaliaSyntax"])
    ],
    targets: [
        .target(name: "MarginaliaSyntax"),
        .testTarget(
            name: "MarginaliaSyntaxTests",
            dependencies: ["MarginaliaSyntax"]
        )
    ]
)
