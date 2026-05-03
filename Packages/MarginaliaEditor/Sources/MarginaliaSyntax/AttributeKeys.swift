import Foundation

public extension NSAttributedString.Key {
    static let marginaliaBlock = NSAttributedString.Key("marginalia.block")
    static let marginaliaListItem = NSAttributedString.Key("marginalia.listItem")
    static let marginaliaLink = NSAttributedString.Key("marginalia.link")
    static let marginaliaInline = NSAttributedString.Key("marginalia.inline")
}

public enum BlockTag: String, Sendable, Hashable, CaseIterable {
    case paragraph
    case heading
    case blockquote
    case unorderedListItem
    case orderedListItem
    case taskListItem
    case fencedCode
    case indentedCode
    case horizontalRule
    case htmlBlock
    case linkReferenceDefinition
    case pipeTable
}

public final class BlockAttribute: NSObject, @unchecked Sendable {
    public let tag: BlockTag
    public let level: Int
    public let blockquoteDepth: Int
    public let language: String?

    public init(tag: BlockTag, level: Int = 0, blockquoteDepth: Int = 0, language: String? = nil) {
        self.tag = tag
        self.level = level
        self.blockquoteDepth = blockquoteDepth
        self.language = language
    }
}

public enum InlineTag: String, Sendable, Hashable, CaseIterable {
    case emphasis
    case strong
    case strikethrough
    case codeSpan
    case link
    case rawHTML
}

public enum ListItemKind: String, Sendable, Hashable, CaseIterable {
    case bullet
    case ordered
    case task
}

public final class ListItemAttribute: NSObject, @unchecked Sendable {
    public let level: Int
    public let kind: ListItemKind
    public let orderedIndex: Int?
    public let isChecked: Bool?

    public init(level: Int, kind: ListItemKind, orderedIndex: Int? = nil, isChecked: Bool? = nil) {
        self.level = level
        self.kind = kind
        self.orderedIndex = orderedIndex
        self.isChecked = isChecked
    }
}
