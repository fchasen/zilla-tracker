import Testing
import Foundation
@testable import MarginaliaSyntax

@Suite(.serialized) struct EditingOpsTests {

    // MARK: - wrap

    @Test func wrapEmptyTextEmptySelection() {
        let result = EditingOps.wrap(
            in: "",
            selection: NSRange(location: 0, length: 0),
            prefix: "**", suffix: "**", placeholder: "bold"
        )
        #expect(result.text == "**bold**")
        #expect(result.selection == NSRange(location: 2, length: 4))
    }

    @Test func wrapInsertsAtCursorNotAtEnd() {
        let result = EditingOps.wrap(
            in: "hello world",
            selection: NSRange(location: 6, length: 0),
            prefix: "*", suffix: "*", placeholder: "italic"
        )
        #expect(result.text == "hello *italic*world")
        #expect(result.selection == NSRange(location: 7, length: 6))
    }

    @Test func wrapNonEmptySelection() {
        let result = EditingOps.wrap(
            in: "hello world",
            selection: NSRange(location: 0, length: 5),
            prefix: "**", suffix: "**", placeholder: "bold"
        )
        #expect(result.text == "**hello** world")
        #expect(result.selection == NSRange(location: 0, length: 9))
    }

    @Test func wrapSelectionAtEnd() {
        let result = EditingOps.wrap(
            in: "hello world",
            selection: NSRange(location: 6, length: 5),
            prefix: "**", suffix: "**", placeholder: "bold"
        )
        #expect(result.text == "hello **world**")
        #expect(result.selection == NSRange(location: 6, length: 9))
    }

    @Test func wrapAsymmetricMarkers() {
        let result = EditingOps.wrap(
            in: "click here",
            selection: NSRange(location: 0, length: 5),
            prefix: "[", suffix: "](url)", placeholder: "label"
        )
        #expect(result.text == "[click](url) here")
        #expect(result.selection == NSRange(location: 0, length: 12))
    }

    @Test func wrapPreservesUnicodeUTF16Lengths() {
        // 🚀 is one Character, two UTF-16 code units
        let result = EditingOps.wrap(
            in: "🚀x",
            selection: NSRange(location: 2, length: 1),
            prefix: "*", suffix: "*", placeholder: "italic"
        )
        #expect(result.text == "🚀*x*")
        #expect(result.selection == NSRange(location: 2, length: 3))
    }

    // MARK: - prefixLines

    @Test func prefixLinesEmptyText() {
        let result = EditingOps.prefixLines(
            in: "",
            selection: NSRange(location: 0, length: 0),
            marker: "- "
        )
        #expect(result.text == "- ")
        #expect(result.selection == NSRange(location: 2, length: 0))
    }

    @Test func prefixLinesCursorAtEndOfLine() {
        let result = EditingOps.prefixLines(
            in: "hello",
            selection: NSRange(location: 5, length: 0),
            marker: "- "
        )
        #expect(result.text == "- hello")
        #expect(result.selection == NSRange(location: 7, length: 0))
    }

    @Test func prefixLinesCursorMidLine() {
        let result = EditingOps.prefixLines(
            in: "hello world",
            selection: NSRange(location: 6, length: 0),
            marker: "- "
        )
        #expect(result.text == "- hello world")
        #expect(result.selection == NSRange(location: 8, length: 0))
    }

    @Test func prefixLinesSingleLineSelection() {
        let result = EditingOps.prefixLines(
            in: "hello",
            selection: NSRange(location: 0, length: 5),
            marker: "- "
        )
        #expect(result.text == "- hello")
        #expect(result.selection == NSRange(location: 0, length: 7))
    }

    @Test func prefixLinesMultiLineSelection() {
        let result = EditingOps.prefixLines(
            in: "hello\nworld\nfoo",
            selection: NSRange(location: 0, length: 11),
            marker: "- "
        )
        #expect(result.text == "- hello\n- world\nfoo")
        #expect(result.selection == NSRange(location: 0, length: 15))
    }

    @Test func prefixLinesPartialSelectionExtendsToFullLines() {
        let result = EditingOps.prefixLines(
            in: "hello\nworld\nfoo",
            selection: NSRange(location: 2, length: 5),
            marker: "- "
        )
        #expect(result.text == "- hello\n- world\nfoo")
    }

    @Test func prefixLinesSelectionIncludingTrailingNewline() {
        let result = EditingOps.prefixLines(
            in: "hello\nworld",
            selection: NSRange(location: 0, length: 6),
            marker: "- "
        )
        #expect(result.text == "- hello\nworld")
    }

    @Test func prefixLinesBlockquoteMarker() {
        let result = EditingOps.prefixLines(
            in: "a\nb",
            selection: NSRange(location: 0, length: 3),
            marker: "> "
        )
        #expect(result.text == "> a\n> b")
    }

    // MARK: - numberedList

    @Test func numberedListEmptyText() {
        let result = EditingOps.numberedList(
            in: "",
            selection: NSRange(location: 0, length: 0)
        )
        #expect(result.text == "1. ")
        #expect(result.selection == NSRange(location: 3, length: 0))
    }

    @Test func numberedListCursorOnLine() {
        let result = EditingOps.numberedList(
            in: "hello",
            selection: NSRange(location: 5, length: 0)
        )
        #expect(result.text == "1. hello")
    }

    @Test func numberedListMultiLineSelection() {
        let result = EditingOps.numberedList(
            in: "first\nsecond\nthird",
            selection: NSRange(location: 0, length: 18)
        )
        #expect(result.text == "1. first\n2. second\n3. third")
    }

    @Test func numberedListNumbersExceedingTen() {
        let lines = (1...12).map { "line\($0)" }.joined(separator: "\n")
        let result = EditingOps.numberedList(
            in: lines,
            selection: NSRange(location: 0, length: (lines as NSString).length)
        )
        #expect(result.text.contains("10. line10"))
        #expect(result.text.contains("11. line11"))
        #expect(result.text.contains("12. line12"))
    }

    // MARK: - wrapCodeBlock

    @Test func wrapCodeBlockEmptyText() {
        let result = EditingOps.wrapCodeBlock(
            in: "",
            selection: NSRange(location: 0, length: 0)
        )
        #expect(result.text == "```\ncode\n```\n")
        #expect(result.selection == NSRange(location: 4, length: 4))
    }

    @Test func wrapCodeBlockAtStartOfNewLine() {
        let result = EditingOps.wrapCodeBlock(
            in: "hello\n",
            selection: NSRange(location: 6, length: 0)
        )
        #expect(result.text == "hello\n```\ncode\n```\n")
        #expect(result.selection == NSRange(location: 10, length: 4))
    }

    @Test func wrapCodeBlockMidLineAddsLeadingNewline() {
        let result = EditingOps.wrapCodeBlock(
            in: "hello world",
            selection: NSRange(location: 6, length: 0)
        )
        #expect(result.text == "hello \n```\ncode\n```\nworld")
    }

    @Test func wrapCodeBlockSelectionAtLineStart() {
        let result = EditingOps.wrapCodeBlock(
            in: "let x = 1",
            selection: NSRange(location: 0, length: 9)
        )
        #expect(result.text == "```\nlet x = 1\n```\n")
    }

    @Test func wrapCodeBlockSelectionWithTrailingNewline() {
        let result = EditingOps.wrapCodeBlock(
            in: "let x = 1\n",
            selection: NSRange(location: 0, length: 10)
        )
        #expect(result.text == "```\nlet x = 1\n```\n")
    }

    @Test func wrapCodeBlockSelectionMidLine() {
        let result = EditingOps.wrapCodeBlock(
            in: "before code after",
            selection: NSRange(location: 7, length: 4)
        )
        #expect(result.text == "before \n```\ncode\n```\n after")
    }

    @Test func wrapCodeBlockCustomPlaceholder() {
        let result = EditingOps.wrapCodeBlock(
            in: "",
            selection: NSRange(location: 0, length: 0),
            placeholder: "swift"
        )
        #expect(result.text == "```\nswift\n```\n")
        #expect(result.selection == NSRange(location: 4, length: 5))
    }

    // MARK: - insertHorizontalRule

    @Test func insertHorizontalRuleAtStartOfEmptyText() {
        let result = EditingOps.insertHorizontalRule(
            in: "",
            selection: NSRange(location: 0, length: 0)
        )
        #expect(result.text == "---\n\n")
        #expect(result.selection == NSRange(location: 5, length: 0))
    }

    @Test func insertHorizontalRuleAtStartOfLineSkipsLeadingNewline() {
        let result = EditingOps.insertHorizontalRule(
            in: "first\n",
            selection: NSRange(location: 6, length: 0)
        )
        #expect(result.text == "first\n---\n\n")
    }

    @Test func insertHorizontalRuleMidLineAddsLeadingNewline() {
        let result = EditingOps.insertHorizontalRule(
            in: "hello world",
            selection: NSRange(location: 6, length: 0)
        )
        #expect(result.text == "hello \n---\n\nworld")
    }

    // MARK: - indentListLines / outdentListLines

    @Test func indentBulletListItem() {
        let result = EditingOps.indentListLines(
            in: "- one",
            selection: NSRange(location: 5, length: 0)
        )
        #expect(result?.text == "  - one")
        #expect(result?.selection == NSRange(location: 7, length: 0))
    }

    @Test func indentNumberedListItem() {
        let result = EditingOps.indentListLines(
            in: "1. one",
            selection: NSRange(location: 6, length: 0)
        )
        #expect(result?.text == "  1. one")
    }

    @Test func indentNonListLineReturnsNil() {
        let result = EditingOps.indentListLines(
            in: "just prose",
            selection: NSRange(location: 4, length: 0)
        )
        #expect(result == nil)
    }

    @Test func outdentRemovesTwoSpaceIndent() {
        let result = EditingOps.outdentListLines(
            in: "  - nested",
            selection: NSRange(location: 5, length: 0)
        )
        #expect(result?.text == "- nested")
        #expect(result?.selection == NSRange(location: 3, length: 0))
    }

    @Test func outdentRemovesTab() {
        let result = EditingOps.outdentListLines(
            in: "\t- nested",
            selection: NSRange(location: 4, length: 0)
        )
        #expect(result?.text == "- nested")
    }

    @Test func outdentWithoutLeadingIndentReturnsNil() {
        let result = EditingOps.outdentListLines(
            in: "- top-level",
            selection: NSRange(location: 5, length: 0)
        )
        #expect(result == nil)
    }

    @Test func indentMultipleLinesPrefixesEachListLine() {
        let result = EditingOps.indentListLines(
            in: "- one\n- two\nplain",
            selection: NSRange(location: 0, length: 17)
        )
        #expect(result?.text == "  - one\n  - two\nplain")
    }

    // MARK: - applyListMarker (smart list-button behavior)

    @Test func applyBulletOnBulletIndents() {
        let result = EditingOps.applyListMarker(
            in: "- one",
            selection: NSRange(location: 5, length: 0),
            kind: .bullet
        )
        #expect(result?.text == "  - one")
    }

    @Test func applyBulletOnNumberedSwitchesToBullet() {
        let result = EditingOps.applyListMarker(
            in: "1. one",
            selection: NSRange(location: 6, length: 0),
            kind: .bullet
        )
        #expect(result?.text == "- one")
    }

    @Test func applyNumberedOnTaskSwitchesToNumbered() {
        let result = EditingOps.applyListMarker(
            in: "- [ ] task",
            selection: NSRange(location: 10, length: 0),
            kind: .numbered
        )
        #expect(result?.text == "1. task")
    }

    @Test func applyTaskOnBulletSwitchesToTask() {
        let result = EditingOps.applyListMarker(
            in: "- one",
            selection: NSRange(location: 5, length: 0),
            kind: .task
        )
        #expect(result?.text == "- [ ] one")
    }

    @Test func applyBulletOnPlainAddsMarker() {
        let result = EditingOps.applyListMarker(
            in: "plain prose",
            selection: NSRange(location: 5, length: 0),
            kind: .bullet
        )
        #expect(result?.text == "- plain prose")
    }

    @Test func applyTaskOnTaskIndents() {
        let result = EditingOps.applyListMarker(
            in: "- [ ] task",
            selection: NSRange(location: 10, length: 0),
            kind: .task
        )
        #expect(result?.text == "  - [ ] task")
    }

    @Test func applyNumberedOnNumberedIndents() {
        let result = EditingOps.applyListMarker(
            in: "1. one",
            selection: NSRange(location: 6, length: 0),
            kind: .numbered
        )
        #expect(result?.text == "  1. one")
    }

    @Test func switchPreservesLeadingIndent() {
        let result = EditingOps.applyListMarker(
            in: "  - nested",
            selection: NSRange(location: 10, length: 0),
            kind: .numbered
        )
        #expect(result?.text == "  1. nested")
    }

    // MARK: - defensive bounds

    @Test func prefixLinesWithStaleSelectionDoesNotCrash() {
        // `lineRangeExcludingTerminator` used to crash inside `lineRange(for:)`
        // when handed a selection past the text end. Clamping internally
        // turns it into a no-op insert at the end.
        _ = EditingOps.prefixLines(
            in: "short",
            selection: NSRange(location: 999, length: 100),
            marker: "- "
        )
    }

    @Test func indentListLinesWithStaleSelectionDoesNotCrash() {
        let result = EditingOps.indentListLines(
            in: "- item",
            selection: NSRange(location: 999, length: 100)
        )
        // May return nil (not a list line at the clamped position) but
        // must not crash.
        _ = result
    }

    @Test func outdentListLinesWithStaleSelectionDoesNotCrash() {
        let result = EditingOps.outdentListLines(
            in: "  - item",
            selection: NSRange(location: 999, length: 100)
        )
        _ = result
    }

    // MARK: - EditResult

    @Test func editResultEquality() {
        let a = EditResult(text: "hello", selection: NSRange(location: 1, length: 2))
        let b = EditResult(text: "hello", selection: NSRange(location: 1, length: 2))
        let c = EditResult(text: "world", selection: NSRange(location: 1, length: 2))
        #expect(a == b)
        #expect(a != c)
    }
}
