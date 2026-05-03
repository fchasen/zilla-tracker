import Testing
import Foundation
import MarginaliaSyntax
@testable import MarginaliaView
#if canImport(AppKit) && os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

@Suite(.serialized) struct OperationsTests {

    private func compile(_ markdown: String) throws -> NSTextStorage {
        let compiler = try MarkdownAttributedCompiler()
        let attr = compiler.compile(markdown, dialect: .commonMark, mode: .rich, theme: .default)
        return NSTextStorage(attributedString: attr)
    }

    private func serialize(_ storage: NSTextStorage) -> String {
        AttributedMarkdownSerializer().serialize(storage, dialect: .commonMark)
    }

    @Test func toggleBoldAddsStrongRoundtrip() throws {
        let storage = try compile("hello world\n")
        Operations.toggleBold(in: storage, range: NSRange(location: 0, length: 5), theme: .default)
        #expect(serialize(storage) == "**hello** world\n")
    }

    @Test func toggleBoldRemovesStrong() throws {
        let storage = try compile("**hello** world\n")
        // The "hello" run is bold in compiled storage. Range to it.
        Operations.toggleBold(in: storage, range: NSRange(location: 0, length: 5), theme: .default)
        #expect(serialize(storage) == "hello world\n")
    }

    @Test func toggleBoldEmptySelectionInsertsPlaceholder() throws {
        let storage = try compile("ready\n")
        // Cursor before "ready"
        let new = Operations.toggleBold(in: storage, range: NSRange(location: 0, length: 0), theme: .default)
        #expect(new == NSRange(location: 0, length: 4))
        #expect(serialize(storage) == "**bold**ready\n")
    }

    @Test func toggleItalicAddsEmphasis() throws {
        let storage = try compile("hello world\n")
        Operations.toggleItalic(in: storage, range: NSRange(location: 0, length: 5), theme: .default)
        #expect(serialize(storage) == "*hello* world\n")
    }

    @Test func toggleStrikethroughAddsTilde() throws {
        let storage = try compile("done world\n")
        Operations.toggleStrikethrough(in: storage, range: NSRange(location: 0, length: 4), theme: .default)
        #expect(serialize(storage) == "~~done~~ world\n")
    }

    @Test func toggleCodeSpanWrapsInBackticks() throws {
        let storage = try compile("call foo here\n")
        Operations.toggleCodeSpan(in: storage, range: NSRange(location: 5, length: 3), theme: .default)
        #expect(serialize(storage) == "call `foo` here\n")
    }

    @Test func insertLinkAtCursorEmitsMarkdown() throws {
        let storage = try compile("see also\n")
        // Cursor at end of "see also" (before newline)
        Operations.insertLink(in: storage, replacing: NSRange(location: 8, length: 0), label: "docs", url: "https://example.com", theme: .default)
        let out = serialize(storage)
        #expect(out.contains("[docs](https://example.com)"))
    }

    @Test func insertTextAtCursorInheritsParagraph() throws {
        let storage = try compile("# heading\n")
        // Cursor between 'h' and 'eading'
        Operations.insertText(in: storage, replacing: NSRange(location: 1, length: 0), with: "X")
        // Storage rendered = "hXeading" with heading block attribute
        let out = serialize(storage)
        #expect(out == "# hXeading\n")
    }
}
