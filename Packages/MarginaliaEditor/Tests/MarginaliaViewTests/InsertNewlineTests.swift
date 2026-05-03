import Testing
import Foundation
import MarginaliaSyntax
@testable import MarginaliaView
#if canImport(AppKit) && os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

@Suite(.serialized) struct InsertNewlineTests {

    private func storage(from markdown: String) throws -> NSTextStorage {
        let compiler = try MarkdownAttributedCompiler()
        let attr = compiler.compile(markdown, dialect: .commonMark, mode: .rich, theme: .default)
        return NSTextStorage(attributedString: attr)
    }

    private func serialize(_ storage: NSTextStorage) -> String {
        AttributedMarkdownSerializer().serialize(storage, dialect: .commonMark)
    }

    private func handle(in storage: NSTextStorage, cursor: Int) throws -> NSRange? {
        let compiler = try MarkdownAttributedCompiler()
        let serializer = AttributedMarkdownSerializer()
        return InsertNewline.handle(
            in: storage,
            cursor: cursor,
            compiler: compiler,
            serializer: serializer,
            dialect: .commonMark,
            mode: .rich,
            theme: .default
        )
    }

    @Test func nonListReturnsNil() throws {
        let s = try storage(from: "hello\n")
        #expect(try handle(in: s, cursor: 5) == nil)
    }

    @Test func bulletListContinues() throws {
        // Storage = "one\n" with .marginaliaListItem applied; cursor at end of "one".
        let s = try storage(from: "- one\n")
        let result = try handle(in: s, cursor: s.length - 1)
        #expect(result != nil)
        #expect(serialize(s) == "- one\n- \n")
    }

    // emptyBulletTerminatesList: deferred — tree-sitter doesn't always
    // segment a trailing empty bullet line as a list-item, so the handler
    // can't see the .marginaliaListItem attribute it needs to dispatch.
    // Phase 5 polish: detect the empty trailing line via raw text shape
    // and terminate when the user double-Returns.

    @Test func orderedListIncrements() throws {
        let s = try storage(from: "1. apple\n")
        _ = try handle(in: s, cursor: s.length - 1)
        #expect(serialize(s) == "1. apple\n2. \n")
    }

    @Test func taskListContinues() throws {
        let s = try storage(from: "- [x] done\n")
        _ = try handle(in: s, cursor: s.length - 1)
        let out = serialize(s)
        #expect(out.contains("- [x] done"))
        #expect(out.contains("- [ ] "))
    }
}
