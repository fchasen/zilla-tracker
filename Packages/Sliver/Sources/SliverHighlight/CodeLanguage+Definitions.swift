import Foundation
import SwiftTreeSitter
import TreeSitterJavaScript

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
}
