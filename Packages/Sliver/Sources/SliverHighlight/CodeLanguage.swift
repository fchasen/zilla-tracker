import Foundation
import SwiftTreeSitter

public struct CodeLanguage: @unchecked Sendable, Hashable {
    public let id: String
    public let displayName: String
    public let extensions: Set<String>
    public let lineComment: String?
    public let blockCommentOpen: String?
    public let blockCommentClose: String?
    public let parentID: String?
    public let bundle: Bundle?
    public let queryResource: String?
    public let language: Language?

    public init(
        id: String,
        displayName: String,
        extensions: Set<String>,
        lineComment: String? = nil,
        blockCommentOpen: String? = nil,
        blockCommentClose: String? = nil,
        parentID: String? = nil,
        bundle: Bundle? = nil,
        queryResource: String? = nil,
        language: Language? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.extensions = extensions
        self.lineComment = lineComment
        self.blockCommentOpen = blockCommentOpen
        self.blockCommentClose = blockCommentClose
        self.parentID = parentID
        self.bundle = bundle
        self.queryResource = queryResource
        self.language = language
    }

    public static let plain = CodeLanguage(
        id: "plain",
        displayName: "Plain",
        extensions: []
    )

    public static func == (lhs: CodeLanguage, rhs: CodeLanguage) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
