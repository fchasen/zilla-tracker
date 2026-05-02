import Testing
import Foundation
@testable import MarginaliaSyntax

@Suite(.serialized) struct HiddenRangeComputerTests {

    @Test func noMarkupYieldsEmpty() {
        let hidden = HiddenRangeComputer.hiddenRanges(
            markupRanges: [],
            cursorRange: NSRange(location: 0, length: 0),
            in: "plain"
        )
        #expect(hidden == [])
    }

    @Test func cursorOnSameLineAsMarkupKeepsVisible() {
        // "**bold**" on a single line, cursor at offset 3 (inside)
        // The two `**` markup ranges should NOT be hidden.
        let asterisksLeft = NSRange(location: 0, length: 2)
        let asterisksRight = NSRange(location: 6, length: 2)
        let hidden = HiddenRangeComputer.hiddenRanges(
            markupRanges: [asterisksLeft, asterisksRight],
            cursorRange: NSRange(location: 3, length: 0),
            in: "**bold**"
        )
        #expect(hidden == [])
    }

    @Test func cursorOnDifferentLineHidesMarkup() {
        // line 0 = "**bold**", line 1 = "next"
        // Cursor on line 1 → markup on line 0 should be hidden.
        let text = "**bold**\nnext"
        let asterisksLeft = NSRange(location: 0, length: 2)
        let asterisksRight = NSRange(location: 6, length: 2)
        let cursor = NSRange(location: 9, length: 0)  // inside "next"
        let hidden = HiddenRangeComputer.hiddenRanges(
            markupRanges: [asterisksLeft, asterisksRight],
            cursorRange: cursor,
            in: text
        )
        #expect(hidden == [asterisksLeft, asterisksRight])
    }

    @Test func multipleLinesOnlyActiveLineKept() {
        // line 0 = "**a**", line 1 = "**b**", line 2 = "**c**"
        // Cursor on line 1 → line 0 + line 2 markup hidden, line 1 visible.
        let text = "**a**\n**b**\n**c**"
        let line0Markup1 = NSRange(location: 0, length: 2)
        let line0Markup2 = NSRange(location: 3, length: 2)
        let line1Markup1 = NSRange(location: 6, length: 2)
        let line1Markup2 = NSRange(location: 9, length: 2)
        let line2Markup1 = NSRange(location: 12, length: 2)
        let line2Markup2 = NSRange(location: 15, length: 2)

        let cursor = NSRange(location: 8, length: 0)  // inside "**b**"
        let hidden = HiddenRangeComputer.hiddenRanges(
            markupRanges: [line0Markup1, line0Markup2, line1Markup1, line1Markup2, line2Markup1, line2Markup2],
            cursorRange: cursor,
            in: text
        )
        #expect(hidden == [line0Markup1, line0Markup2, line2Markup1, line2Markup2])
    }

    @Test func selectionTouchingTwoLinesKeepsBothVisible() {
        let text = "**a**\n**b**\n**c**"
        let line0M = NSRange(location: 0, length: 2)
        let line1M = NSRange(location: 6, length: 2)
        let line2M = NSRange(location: 12, length: 2)

        // Selection spans line 0 and line 1
        let selection = NSRange(location: 4, length: 4)  // crosses \n
        let hidden = HiddenRangeComputer.hiddenRanges(
            markupRanges: [line0M, line1M, line2M],
            cursorRange: selection,
            in: text
        )
        #expect(hidden == [line2M])
    }

    @Test func cursorAtEndOfFile() {
        let text = "**a**\n**b**"
        let line0M = NSRange(location: 0, length: 2)
        let line1M = NSRange(location: 6, length: 2)
        let cursor = NSRange(location: 11, length: 0)
        let hidden = HiddenRangeComputer.hiddenRanges(
            markupRanges: [line0M, line1M],
            cursorRange: cursor,
            in: text
        )
        #expect(hidden == [line0M])
    }

    // MARK: - defensive clamping

    @Test func staleCursorRangePastEndDoesNotCrash() {
        // The historical NSRangeException: cursor at 62 against a 58-length
        // text (e.g. after a Shift-Tab outdent that shrunk the text but
        // before `selection` was clamped). Must clamp internally.
        let text = "short text only 58 characters long ........... yes" + "..."
        #expect((text as NSString).length == 53)
        let cursor = NSRange(location: 200, length: 0)
        let markup = [NSRange(location: 0, length: 1)]
        // No crash:
        _ = HiddenRangeComputer.hiddenRanges(
            markupRanges: markup,
            cursorRange: cursor,
            in: text
        )
    }

    @Test func staleMarkupRangePastEndDoesNotCrash() {
        let text = "abc"
        let stale = [NSRange(location: 100, length: 5)]
        let cursor = NSRange(location: 0, length: 0)
        _ = HiddenRangeComputer.hiddenRanges(
            markupRanges: stale,
            cursorRange: cursor,
            in: text
        )
    }

    @Test func headingHashHiddenWhenCursorElsewhere() {
        let text = "# heading\nbody\n"
        let headingHash = NSRange(location: 0, length: 1)
        let cursor = NSRange(location: 12, length: 0)  // in "body"
        let hidden = HiddenRangeComputer.hiddenRanges(
            markupRanges: [headingHash],
            cursorRange: cursor,
            in: text
        )
        #expect(hidden == [headingHash])
    }
}
