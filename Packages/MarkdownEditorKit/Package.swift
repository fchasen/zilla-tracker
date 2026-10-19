// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "MarkdownEditorKit",
    platforms: [
        .macOS("26.0"),
        .iOS("26.0")
    ],
    products: [
        .library(name: "MarkdownEditorKit", targets: ["MarkdownEditorKit"])
    ],
    dependencies: [
        .package(path: "../PhabricatorKit")
    ],
    targets: [
        .target(name: "MarkdownEditorKit"),
        .testTarget(
            name: "MarkdownEditorKitTests",
            dependencies: [
                "MarkdownEditorKit",
                .product(name: "PhabricatorKit", package: "PhabricatorKit")
            ]
        )
    ]
)
