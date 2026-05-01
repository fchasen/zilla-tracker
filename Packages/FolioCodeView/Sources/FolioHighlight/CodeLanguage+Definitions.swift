import Foundation
import SwiftTreeSitter
import TreeSitterJavaScript
import TreeSitterTypeScript
import TreeSitterPython
import TreeSitterRust
import TreeSitterC
import TreeSitterCPP
import TreeSitterJSON
import TreeSitterHTML
import TreeSitterCSS
import TreeSitterSwift
import TreeSitterMarkdown

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

    static let c = CodeLanguage(
        id: "c",
        displayName: "C",
        extensions: ["c", "h"],
        lineComment: "//",
        blockCommentOpen: "/*",
        blockCommentClose: "*/",
        bundle: .module,
        queryResource: "c-highlights",
        language: Language(language: tree_sitter_c())
    )

    static let cpp = CodeLanguage(
        id: "cpp",
        displayName: "C++",
        extensions: ["cpp", "cc", "cxx", "hpp", "hh", "hxx", "ipp"],
        lineComment: "//",
        blockCommentOpen: "/*",
        blockCommentClose: "*/",
        parentID: "c",
        bundle: .module,
        queryResource: "cpp-highlights",
        language: Language(language: tree_sitter_cpp())
    )

    static let json = CodeLanguage(
        id: "json",
        displayName: "JSON",
        extensions: ["json", "jsonc"],
        bundle: .module,
        queryResource: "json-highlights",
        language: Language(language: tree_sitter_json())
    )

    static let html = CodeLanguage(
        id: "html",
        displayName: "HTML",
        extensions: ["html", "htm", "xhtml"],
        blockCommentOpen: "<!--",
        blockCommentClose: "-->",
        bundle: .module,
        queryResource: "html-highlights",
        language: Language(language: tree_sitter_html())
    )

    static let css = CodeLanguage(
        id: "css",
        displayName: "CSS",
        extensions: ["css"],
        blockCommentOpen: "/*",
        blockCommentClose: "*/",
        bundle: .module,
        queryResource: "css-highlights",
        language: Language(language: tree_sitter_css())
    )

    static let swift = CodeLanguage(
        id: "swift",
        displayName: "Swift",
        extensions: ["swift"],
        lineComment: "//",
        blockCommentOpen: "/*",
        blockCommentClose: "*/",
        bundle: .module,
        queryResource: "swift-highlights",
        language: Language(language: tree_sitter_swift())
    )

    static let markdown = CodeLanguage(
        id: "markdown",
        displayName: "Markdown",
        extensions: ["md", "markdown", "mdx"],
        bundle: .module,
        queryResource: "markdown-highlights",
        language: Language(language: tree_sitter_markdown())
    )
}
