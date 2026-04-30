import Foundation

public struct CodeLanguage: Sendable, Hashable {
    public let id: String
    public let displayName: String
    public let extensions: Set<String>
    public let lineComment: String?
    public let blockCommentOpen: String?
    public let blockCommentClose: String?
    public let parentID: String?
    public let queryResource: String?

    public init(
        id: String,
        displayName: String,
        extensions: Set<String>,
        lineComment: String? = nil,
        blockCommentOpen: String? = nil,
        blockCommentClose: String? = nil,
        parentID: String? = nil,
        queryResource: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.extensions = extensions
        self.lineComment = lineComment
        self.blockCommentOpen = blockCommentOpen
        self.blockCommentClose = blockCommentClose
        self.parentID = parentID
        self.queryResource = queryResource
    }

    public static let plain = CodeLanguage(
        id: "plain",
        displayName: "Plain",
        extensions: []
    )
}
