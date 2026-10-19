import Foundation
import Testing
@testable import MarkdownEditorKit
#if canImport(AppKit) && os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

final class WriterTestAtom: NSTextAttachment, MarkdownSourceAttachment {
    var markdownSource: String
    var contentKind: String

    init(source: String, kind: String) {
        markdownSource = source
        contentKind = kind
        super.init(data: nil, ofType: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("unused")
    }
}

enum WF {
    typealias Marks = EditorDocument.InlineMarks

    struct Para {
        var content: [NSAttributedString]
        var block: MarkdownBlock
        var lists: [NSTextList]
    }

    static func t(_ string: String, _ marks: Marks = [], link: String? = nil, literal: String? = nil) -> NSAttributedString {
        var attributes: [NSAttributedString.Key: Any] = [:]
        if !marks.isEmpty { attributes[.markdownInlineIntent] = marks.intent.attributeValue }
        if let link { attributes[.link] = link }
        if let literal { attributes[.markdownLiteral] = literal }
        return NSAttributedString(string: string, attributes: attributes)
    }

    static var soft: NSAttributedString {
        NSAttributedString(string: MarkdownBreak.string, attributes: [
            .markdownInlineIntent: MarkdownInlineIntent.softBreak.attributeValue
        ])
    }

    static var hard: NSAttributedString {
        NSAttributedString(string: MarkdownBreak.string)
    }

    static func atom(_ source: String, kind: String = "test.atom", _ marks: Marks = []) -> NSAttributedString {
        let string = NSMutableAttributedString(attachment: WriterTestAtom(source: source, kind: kind))
        if !marks.isEmpty {
            string.addAttribute(.markdownInlineIntent, value: marks.intent.attributeValue, range: NSRange(location: 0, length: string.length))
        }
        return string
    }

    static func p(_ content: NSAttributedString..., block: MarkdownBlock = .paragraph, lists: [NSTextList] = []) -> Para {
        Para(content: content, block: block, lists: lists)
    }

    static func p(_ text: String, block: MarkdownBlock = .paragraph, lists: [NSTextList] = []) -> Para {
        Para(content: text.isEmpty ? [] : [t(text)], block: block, lists: lists)
    }

    static func item(_ text: String, _ lists: [NSTextList], task: TaskState? = nil, continuation: Bool = false, quotes: [GroupToken] = []) -> Para {
        let containers = quotes.map(MarkdownBlock.Container.quote) + lists.map { _ in .listItem }
        let block = MarkdownBlock(containers: containers, isContinuation: continuation, task: task)
        return p(text, block: block, lists: lists)
    }

    static func code(_ line: String, _ group: GroupToken, language: String? = nil, containers: [MarkdownBlock.Container] = [], lists: [NSTextList] = [], continuation: Bool = false) -> Para {
        let block = MarkdownBlock(leaf: .code(language: language, group: group), containers: containers, isContinuation: continuation)
        return p(line, block: block, lists: lists)
    }

    static func bullet() -> NSTextList {
        NSTextList(markerFormat: .disc, options: 0)
    }

    static func ordered(_ start: Int = 1) -> NSTextList {
        let list = NSTextList(markerFormat: .decimal, options: 0)
        list.startingItemNumber = start
        return list
    }

    static func carrier() -> NSTextList {
        NSTextList(markerFormat: NSTextList.MarkerFormat(rawValue: ""), options: 0)
    }

    static func storage(_ paragraphs: [Para], trailingNewline: Bool = false) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for (index, paragraph) in paragraphs.enumerated() {
            let start = result.length
            for piece in paragraph.content { result.append(piece) }
            if index < paragraphs.count - 1 || trailingNewline {
                result.append(NSAttributedString(string: "\n"))
            }
            let range = NSRange(location: start, length: result.length - start)
            guard range.length > 0 else { continue }
            result.addAttribute(.markdownBlock, value: paragraph.block, range: range)
            if !paragraph.lists.isEmpty {
                let style = NSMutableParagraphStyle()
                style.textLists = paragraph.lists
                result.addAttribute(.paragraphStyle, value: style, range: range)
            }
        }
        return result
    }

    static func write(_ paragraphs: Para..., trailingNewline: Bool = false) -> String {
        write(paragraphs, trailingNewline: trailingNewline)
    }

    static func write(_ paragraphs: [Para], trailingNewline: Bool = false) -> String {
        MarkdownWriter().markdown(from: storage(paragraphs, trailingNewline: trailingNewline))
    }

    static func inline(_ content: NSAttributedString...) -> String {
        write([Para(content: content, block: .paragraph, lists: [])])
    }
}

@Suite("Writer fixture")
struct WriterFixtureTests {
    @Test func fixtureBuildsVocabularyAttributes() {
        let list = WF.bullet()
        let storage = WF.storage([WF.p(WF.t("a", .strong)), WF.item("b", [list])])
        #expect(storage.string == "a\nb")
        #expect(storage.markdownInlineIntent(at: 0) == .stronglyEmphasized)
        #expect(storage.markdownBlock(at: 2)?.isListItemStart == true)
        let style = storage.attribute(.paragraphStyle, at: 2, effectiveRange: nil) as? NSParagraphStyle
        #expect(style?.textLists.first === list)
    }

    @Test func readerBuildsDocumentTree() {
        let list = WF.ordered(3)
        let quote = GroupToken.mint()
        let document = StorageReader().document(from: WF.storage([
            WF.p(WF.t("x", [.strong, .emphasis])),
            WF.item("a", [list], task: .checked),
            WF.item("b", [list], quotes: [quote])
        ]))
        #expect(document.blocks == [
            .paragraph([.text("x", marks: [.strong, .emphasis])]),
            .list(.init(kind: .ordered(start: 3), items: [
                .init(task: .checked, blocks: [.paragraph([.text("a")])])
            ])),
            .quote([
                .list(.init(kind: .ordered(start: 3), items: [
                    .init(blocks: [.paragraph([.text("b")])])
                ]))
            ])
        ])
    }

    @Test func rangeSerializationClipsToParagraphs() {
        let storage = WF.storage([WF.p("abc"), WF.p("def")])
        #expect(MarkdownWriter().markdown(from: storage, range: NSRange(location: 1, length: 4)) == "bc\n\nd")
    }
}
