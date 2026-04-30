// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Sliver",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "Sliver", targets: ["Sliver"]),
        .library(name: "SliverModel", targets: ["SliverModel"]),
        .library(name: "SliverHighlight", targets: ["SliverHighlight"])
    ],
    dependencies: [
        .package(url: "https://github.com/tree-sitter/swift-tree-sitter", from: "0.10.0")
    ],
    targets: [
        .target(name: "SliverModel"),

        .target(
            name: "TreeSitterJavaScript",
            path: "Vendor/tree-sitter-javascript",
            exclude: [
                "grammar.js",
                "src/grammar.json",
                "src/node-types.json",
                "queries"
            ],
            sources: ["src/parser.c", "src/scanner.c"],
            publicHeadersPath: "bindings/swift/TreeSitterJavaScript",
            cSettings: [.headerSearchPath("src")]
        ),
        .target(
            name: "TreeSitterTypeScript",
            path: "Vendor/tree-sitter-typescript",
            exclude: [
                "grammar.js",
                "src/grammar.json",
                "src/node-types.json",
                "queries"
            ],
            sources: ["src/parser.c", "src/scanner.c"],
            publicHeadersPath: "bindings/swift/TreeSitterTypeScript",
            cSettings: [.headerSearchPath("src")]
        ),

        .target(
            name: "SliverHighlight",
            dependencies: [
                .product(name: "SwiftTreeSitter", package: "swift-tree-sitter"),
                "TreeSitterJavaScript",
                "TreeSitterTypeScript"
            ],
            resources: [.copy("Queries")]
        ),
        .target(
            name: "Sliver",
            dependencies: ["SliverModel", "SliverHighlight"]
        ),
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
