import Foundation
import MarginaliaSyntax
import MarginaliaRendering
#if canImport(AppKit) && os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

public final class EditorController {

    public typealias Dialect = MarginaliaView.Dialect

    public let textStorage: NSTextStorage
    public let contentStorage: NSTextContentStorage
    public let layoutManager: NSTextLayoutManager
    public let textContainer: NSTextContainer

    public var theme: MarginaliaTheme {
        didSet { recompile() }
    }
    public var dialect: Dialect {
        didSet { recompile() }
    }
    public var mode: Mode {
        didSet { recompile() }
    }

    public private(set) var blocks: [BlockSegment] = []

    public let undoManager: UndoManager = UndoManager()
    public weak var hostTextView: AnyObject?
    public var intrinsicSizeInvalidator: (() -> Void)?

    private let compiler: MarkdownAttributedCompiler
    private let serializer: AttributedMarkdownSerializer
    private let layoutDelegate: LayoutManagerDelegate
    private var storageObserver: NSObjectProtocol?
    private var applyingMarkdown = false

    public init(
        initialMarkdown: String = "",
        theme: MarginaliaTheme = .default,
        dialect: Dialect = .commonMark,
        mode: Mode = .rich,
        containerSize: CGSize = CGSize(width: 600, height: CGFloat.greatestFiniteMagnitude)
    ) throws {
        self.theme = theme
        self.dialect = dialect
        self.mode = mode
        self.compiler = try MarkdownAttributedCompiler()
        self.serializer = AttributedMarkdownSerializer()

        self.textStorage = NSTextStorage()
        self.contentStorage = NSTextContentStorage()
        self.contentStorage.textStorage = textStorage
        self.layoutManager = NSTextLayoutManager()
        self.contentStorage.addTextLayoutManager(layoutManager)
        self.textContainer = NSTextContainer(size: containerSize)
        self.layoutManager.textContainer = textContainer

        self.layoutDelegate = LayoutManagerDelegate()
        layoutManager.delegate = layoutDelegate
        layoutDelegate.controller = self

        applyingMarkdown = true
        let initial = compileFor(initialMarkdown)
        textStorage.replaceCharacters(in: NSRange(location: 0, length: 0), with: initial)
        applyingMarkdown = false
        resegment()

        storageObserver = NotificationCenter.default.addObserver(
            forName: NSTextStorage.didProcessEditingNotification,
            object: textStorage,
            queue: nil
        ) { [weak self] _ in
            guard let self, !self.applyingMarkdown else { return }
            if self.textStorage.editedMask.contains(.editedCharacters) {
                self.resegment()
                self.intrinsicSizeInvalidator?()
            }
        }
    }

    deinit {
        if let storageObserver {
            NotificationCenter.default.removeObserver(storageObserver)
        }
    }

    public func setMarkdown(_ markdown: String) {
        let compiled = compileFor(markdown)
        replaceStorage(with: compiled)
    }

    public var text: String {
        get { markdown() }
        set { setMarkdown(newValue) }
    }

    public func markdown() -> String {
        return serializer.serialize(textStorage, dialect: dialect)
    }

    public func recompile() {
        let md = markdown()
        setMarkdown(md)
    }

    // MARK: - private

    private func compileFor(_ markdown: String) -> NSAttributedString {
        return compiler.compile(markdown, dialect: dialect, mode: mode, theme: theme)
    }

    private func replaceStorage(with attributed: NSAttributedString) {
        applyingMarkdown = true
        let total = NSRange(location: 0, length: textStorage.length)
        textStorage.beginEditing()
        textStorage.replaceCharacters(in: total, with: attributed)
        textStorage.endEditing()
        applyingMarkdown = false
        resegment()
    }

    private func resegment() {
        var segs: [BlockSegment] = []
        let total = textStorage.length
        guard total > 0 else { self.blocks = []; return }
        var cursor = 0
        while cursor < total {
            var range = NSRange(location: cursor, length: 0)
            let attr = textStorage.attribute(
                .marginaliaBlock,
                at: cursor,
                longestEffectiveRange: &range,
                in: NSRange(location: cursor, length: total - cursor)
            )
            if let block = attr as? BlockAttribute {
                let listAttr = textStorage.attribute(
                    .marginaliaListItem, at: cursor, effectiveRange: nil
                ) as? ListItemAttribute
                segs.append(BlockSegment(
                    range: range,
                    tag: block.tag,
                    level: block.level,
                    blockquoteDepth: block.blockquoteDepth,
                    language: block.language,
                    listLevel: listAttr?.level ?? 0,
                    orderedIndex: listAttr?.orderedIndex,
                    isChecked: listAttr?.isChecked,
                    firstInListItem: false
                ))
            }
            if range.length == 0 { break }
            cursor = range.location + range.length
        }
        self.blocks = segs
    }
}
