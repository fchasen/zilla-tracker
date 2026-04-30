import Foundation
import SwiftTreeSitter
import TreeSitterJavaScript
import TreeSitterTypeScript
import TreeSitterPython
import TreeSitterRust

public extension CodeLanguage {
    static let javascript = CodeLanguage(
        id: "javascript",
        displayName: "JavaScript",
        extensions: ["js", "jsx", "mjs", "cjs"],
        lineComment: "//",
        blockCommentOpen: "/*",
        blockCommentClose: "*/",
        bundle: .module,
        queryResource: "javascript-highlights",
        language: Language(language: tree_sitter_javascript())
    )

    static let typescript = CodeLanguage(
        id: "typescript",
        displayName: "TypeScript",
        extensions: ["ts", "mts", "cts"],
        lineComment: "//",
        blockCommentOpen: "/*",
        blockCommentClose: "*/",
        bundle: .module,
        queryResource: "typescript-highlights",
        language: Language(language: tree_sitter_typescript())
    )

    static let python = CodeLanguage(
        id: "python",
        displayName: "Python",
        extensions: ["py", "pyi", "pyw"],
        lineComment: "#",
        bundle: .module,
        queryResource: "python-highlights",
        language: Language(language: tree_sitter_python())
    )

    static let rust = CodeLanguage(
        id: "rust",
        displayName: "Rust",
        extensions: ["rs"],
        lineComment: "//",
        blockCommentOpen: "/*",
        blockCommentClose: "*/",
        bundle: .module,
        queryResource: "rust-highlights",
        language: Language(language: tree_sitter_rust())
    )
}
