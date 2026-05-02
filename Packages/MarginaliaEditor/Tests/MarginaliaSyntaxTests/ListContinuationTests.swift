import Testing
import Foundation
@testable import MarginaliaSyntax

@Suite(.serialized) struct ListContinuationTests {

    // MARK: - Bullet lists

    @Test func bulletContinues() {
        let result = ListContinuation.handleReturn(
            in: "- first",
            cursor: 7
        )
        #expect(result != nil)
        #expect(result?.text == "- first\n- ")
        #expect(result?.selection == NSRange(location: 10, length: 0))
    }

    @Test func emptyBulletItemTerminatesList() {
        let result = ListContinuation.handleReturn(
            in: "- first\n- ",
            cursor: 10
        )
        #expect(result != nil)
        #expect(result?.text == "- first\n")
        #expect(result?.selection == NSRange(location: 8, length: 0))
    }

    @Test func emptyBulletWithOnlyMarkerTerminates() {
        let result = ListContinuation.handleReturn(
            in: "- ",
            cursor: 2
        )
        #expect(result != nil)
        #expect(result?.text == "")
        #expect(result?.selection == NSRange(location: 0, length: 0))
    }

    @Test func bulletContinuesAfterTwoItems() {
        let result = ListContinuation.handleReturn(
            in: "- one\n- two",
            cursor: 11
        )
        #expect(result != nil)
        #expect(result?.text == "- one\n- two\n- ")
        #expect(result?.selection == NSRange(location: 14, length: 0))
    }

    @Test func bulletContinuesWithCursorMidLine() {
        // Cursor mid-line should split: "- foo|bar" + return → "- foo\n- bar"
        let result = ListContinuation.handleReturn(
            in: "- foobar",
            cursor: 5
        )
        #expect(result != nil)
        #expect(result?.text == "- foo\n- bar")
        #expect(result?.selection == NSRange(location: 8, length: 0))
    }

    // MARK: - Numbered lists

    @Test func numberedListContinues() {
        let result = ListContinuation.handleReturn(
            in: "1. first",
            cursor: 8
        )
        #expect(result != nil)
        #expect(result?.text == "1. first\n2. ")
        #expect(result?.selection == NSRange(location: 12, length: 0))
    }

    @Test func numberedListIncrementsBeyondTen() {
        let result = ListContinuation.handleReturn(
            in: "10. tenth",
            cursor: 9
        )
        #expect(result != nil)
        #expect(result?.text == "10. tenth\n11. ")
        #expect(result?.selection == NSRange(location: 14, length: 0))
    }

    @Test func emptyNumberedItemTerminatesList() {
        let result = ListContinuation.handleReturn(
            in: "1. first\n2. ",
            cursor: 12
        )
        #expect(result != nil)
        #expect(result?.text == "1. first\n")
        #expect(result?.selection == NSRange(location: 9, length: 0))
    }

    // MARK: - Task lists

    @Test func taskListBulletContinues() {
        let result = ListContinuation.handleReturn(
            in: "- [ ] task one",
            cursor: 14
        )
        #expect(result != nil)
        #expect(result?.text == "- [ ] task one\n- [ ] ")
        #expect(result?.selection == NSRange(location: 21, length: 0))
    }

    @Test func checkedTaskContinuesWithUnchecked() {
        // After a [x] completed item, the new item starts unchecked
        let result = ListContinuation.handleReturn(
            in: "- [x] done",
            cursor: 10
        )
        #expect(result != nil)
        #expect(result?.text == "- [x] done\n- [ ] ")
        #expect(result?.selection == NSRange(location: 17, length: 0))
    }

    @Test func emptyTaskItemTerminates() {
        let result = ListContinuation.handleReturn(
            in: "- [ ] ",
            cursor: 6
        )
        #expect(result != nil)
        #expect(result?.text == "")
    }

    // MARK: - Indented list items

    @Test func indentedBulletContinues() {
        let result = ListContinuation.handleReturn(
            in: "  - nested",
            cursor: 10
        )
        #expect(result != nil)
        #expect(result?.text == "  - nested\n  - ")
        #expect(result?.selection == NSRange(location: 15, length: 0))
    }

    @Test func indentedEmptyBulletTerminates() {
        let result = ListContinuation.handleReturn(
            in: "  - ",
            cursor: 4
        )
        #expect(result != nil)
        #expect(result?.text == "")
    }

    @Test func tabIndentedBulletContinues() {
        let result = ListContinuation.handleReturn(
            in: "\t- tabbed",
            cursor: 9
        )
        #expect(result != nil)
        #expect(result?.text == "\t- tabbed\n\t- ")
    }

    // MARK: - Blockquote

    @Test func blockquoteContinues() {
        let result = ListContinuation.handleReturn(
            in: "> quoted",
            cursor: 8
        )
        #expect(result != nil)
        #expect(result?.text == "> quoted\n> ")
        #expect(result?.selection == NSRange(location: 11, length: 0))
    }

    @Test func emptyBlockquoteTerminates() {
        let result = ListContinuation.handleReturn(
            in: "> first\n> ",
            cursor: 10
        )
        #expect(result != nil)
        #expect(result?.text == "> first\n")
        #expect(result?.selection == NSRange(location: 8, length: 0))
    }

    // MARK: - No list context

    @Test func returnInPlainTextReturnsNil() {
        let result = ListContinuation.handleReturn(
            in: "just some text",
            cursor: 14
        )
        #expect(result == nil)
    }

    @Test func returnInBlankLineReturnsNil() {
        let result = ListContinuation.handleReturn(
            in: "first\n\nsecond",
            cursor: 6
        )
        #expect(result == nil)
    }

    @Test func returnImmediatelyAfterListReturnsNil() {
        // After list terminated, next return should not auto-continue
        let result = ListContinuation.handleReturn(
            in: "- item\n\n",
            cursor: 8
        )
        #expect(result == nil)
    }

    // MARK: - Multiline source — only the current line matters

    @Test func listContinuesWithUnrelatedTextAbove() {
        let result = ListContinuation.handleReturn(
            in: "Some prose.\n\n- item",
            cursor: 19
        )
        #expect(result != nil)
        #expect(result?.text == "Some prose.\n\n- item\n- ")
    }
}
