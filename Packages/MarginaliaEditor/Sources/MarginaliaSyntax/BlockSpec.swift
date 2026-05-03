import Foundation

public extension NSAttributedString.Key {
    static let marginaliaBlockSpec = NSAttributedString.Key("marginalia.blockSpec")
}

public struct BlockSpec: Equatable, Hashable, Sendable {
    public let kind: Kind
    public let blockquoteDepth: Int
    public let listLevel: Int

    public enum Kind: Equatable, Hashable, Sendable {
        case paragraph
        case heading(level: Int)
        case unorderedListItem
        case orderedListItem(index: Int)
        case taskListItem(checked: Bool)
        case fencedCode(language: String?)
        case indentedCode
        case horizontalRule
        case htmlBlock
        case linkReferenceDefinition
        case pipeTable
    }

    public init(kind: Kind, blockquoteDepth: Int = 0, listLevel: Int = 0) {
        self.kind = kind
        self.blockquoteDepth = max(0, blockquoteDepth)
        self.listLevel = max(0, listLevel)
    }

    public static let paragraph = BlockSpec(kind: .paragraph)

    public var isListItem: Bool {
        switch kind {
        case .unorderedListItem, .orderedListItem, .taskListItem: return true
        default: return false
        }
    }

    public var isCodeBlock: Bool {
        switch kind {
        case .fencedCode, .indentedCode: return true
        default: return false
        }
    }
}

public extension BlockSpec {
    init(blockAttribute: BlockAttribute, listItem: ListItemAttribute? = nil) {
        let depth = blockAttribute.blockquoteDepth
        let level = listItem?.level ?? blockAttribute.level
        switch blockAttribute.tag {
        case .paragraph:
            self.init(kind: .paragraph, blockquoteDepth: depth, listLevel: 0)
        case .heading:
            self.init(kind: .heading(level: blockAttribute.level), blockquoteDepth: depth)
        case .blockquote:
            self.init(kind: .paragraph, blockquoteDepth: max(1, depth))
        case .unorderedListItem:
            self.init(kind: .unorderedListItem, blockquoteDepth: depth, listLevel: level)
        case .orderedListItem:
            self.init(
                kind: .orderedListItem(index: listItem?.orderedIndex ?? 1),
                blockquoteDepth: depth,
                listLevel: level
            )
        case .taskListItem:
            self.init(
                kind: .taskListItem(checked: listItem?.isChecked ?? false),
                blockquoteDepth: depth,
                listLevel: level
            )
        case .fencedCode:
            self.init(kind: .fencedCode(language: blockAttribute.language), blockquoteDepth: depth)
        case .indentedCode:
            self.init(kind: .indentedCode, blockquoteDepth: depth)
        case .horizontalRule:
            self.init(kind: .horizontalRule)
        case .htmlBlock:
            self.init(kind: .htmlBlock, blockquoteDepth: depth)
        case .linkReferenceDefinition:
            self.init(kind: .linkReferenceDefinition, blockquoteDepth: depth)
        case .pipeTable:
            self.init(kind: .pipeTable, blockquoteDepth: depth)
        }
    }

    init(blockSegment: BlockSegment) {
        let depth = blockSegment.blockquoteDepth
        switch blockSegment.tag {
        case .paragraph:
            self.init(kind: .paragraph, blockquoteDepth: depth)
        case .heading:
            self.init(kind: .heading(level: blockSegment.level), blockquoteDepth: depth)
        case .blockquote:
            self.init(kind: .paragraph, blockquoteDepth: max(1, depth))
        case .unorderedListItem:
            self.init(kind: .unorderedListItem, blockquoteDepth: depth, listLevel: blockSegment.listLevel)
        case .orderedListItem:
            self.init(
                kind: .orderedListItem(index: blockSegment.orderedIndex ?? 1),
                blockquoteDepth: depth,
                listLevel: blockSegment.listLevel
            )
        case .taskListItem:
            self.init(
                kind: .taskListItem(checked: blockSegment.isChecked ?? false),
                blockquoteDepth: depth,
                listLevel: blockSegment.listLevel
            )
        case .fencedCode:
            self.init(kind: .fencedCode(language: blockSegment.language), blockquoteDepth: depth)
        case .indentedCode:
            self.init(kind: .indentedCode, blockquoteDepth: depth)
        case .horizontalRule:
            self.init(kind: .horizontalRule)
        case .htmlBlock:
            self.init(kind: .htmlBlock, blockquoteDepth: depth)
        case .linkReferenceDefinition:
            self.init(kind: .linkReferenceDefinition, blockquoteDepth: depth)
        case .pipeTable:
            self.init(kind: .pipeTable, blockquoteDepth: depth)
        }
    }
}

public final class BlockSpecBox: NSObject, @unchecked Sendable {
    public let spec: BlockSpec

    public init(_ spec: BlockSpec) {
        self.spec = spec
        super.init()
    }

    public override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? BlockSpecBox else { return false }
        return spec == other.spec
    }

    public override var hash: Int {
        var hasher = Hasher()
        hasher.combine(spec)
        return hasher.finalize()
    }
}

public extension NSAttributedString {
    func blockSpec(at index: Int) -> BlockSpec? {
        guard index >= 0, index < length else { return nil }
        let raw = attribute(.marginaliaBlockSpec, at: index, effectiveRange: nil)
        return (raw as? BlockSpecBox)?.spec
    }

    func enumerateBlockSpecs(
        in range: NSRange? = nil,
        _ body: (NSRange, BlockSpec) -> Void
    ) {
        let scan = range ?? NSRange(location: 0, length: length)
        guard scan.length > 0 else { return }
        enumerateAttribute(.marginaliaBlockSpec, in: scan) { value, subRange, _ in
            if let box = value as? BlockSpecBox {
                body(subRange, box.spec)
            }
        }
    }
}

public extension NSMutableAttributedString {
    func setBlockSpec(_ spec: BlockSpec, in range: NSRange) {
        guard range.length > 0,
              range.location >= 0,
              range.location + range.length <= length else { return }
        addAttribute(.marginaliaBlockSpec, value: BlockSpecBox(spec), range: range)
    }
}

public extension Dictionary where Key == NSAttributedString.Key, Value == Any {
    var marginaliaBlockSpec: BlockSpec? {
        get { (self[.marginaliaBlockSpec] as? BlockSpecBox)?.spec }
        set {
            if let v = newValue {
                self[.marginaliaBlockSpec] = BlockSpecBox(v)
            } else {
                self[.marginaliaBlockSpec] = nil
            }
        }
    }
}
