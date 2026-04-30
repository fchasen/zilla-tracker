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
    dependencies: [
        .package(url: "https://github.com/tree-sitter/swift-tree-sitter", from: "0.10.0"),
        .package(url: "https://github.com/tree-sitter-grammars/tree-sitter-markdown", from: "0.5.3")
    ],
    targets: [
        .target(
            name: "MarginaliaSyntax",
            dependencies: [
                .product(name: "SwiftTreeSitter", package: "swift-tree-sitter"),
                .product(name: "TreeSitterMarkdown", package: "tree-sitter-markdown")
            ]
        ),
        .testTarget(
            name: "MarginaliaSyntaxTests",
            dependencies: ["MarginaliaSyntax"]
        )
    ]
)
