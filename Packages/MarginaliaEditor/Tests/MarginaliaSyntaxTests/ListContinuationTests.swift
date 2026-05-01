import XCTest
@testable import MarginaliaSyntax

final class ListContinuationTests: XCTestCase {

    // MARK: - Bullet lists

    func testBulletContinues() {
        let result = ListContinuation.handleReturn(
            in: "- first",
            cursor: 7
        )
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.text, "- first\n- ")
        XCTAssertEqual(result?.selection, NSRange(location: 10, length: 0))
    }

    func testEmptyBulletItemTerminatesList() {
        let result = ListContinuation.handleReturn(
            in: "- first\n- ",
            cursor: 10
        )
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.text, "- first\n")
        XCTAssertEqual(result?.selection, NSRange(location: 8, length: 0))
    }

    func testEmptyBulletWithOnlyMarkerTerminates() {
        let result = ListContinuation.handleReturn(
            in: "- ",
            cursor: 2
        )
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.text, "")
        XCTAssertEqual(result?.selection, NSRange(location: 0, length: 0))
    }

    func testBulletContinuesAfterTwoItems() {
        let result = ListContinuation.handleReturn(
            in: "- one\n- two",
            cursor: 11
        )
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.text, "- one\n- two\n- ")
        XCTAssertEqual(result?.selection, NSRange(location: 14, length: 0))
    }

    func testBulletContinuesWithCursorMidLine() {
        // Cursor mid-line should split: "- foo|bar" + return → "- foo\n- bar"
        let result = ListContinuation.handleReturn(
            in: "- foobar",
            cursor: 5
        )
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.text, "- foo\n- bar")
        XCTAssertEqual(result?.selection, NSRange(location: 8, length: 0))
    }

    // MARK: - Numbered lists

    func testNumberedListContinues() {
        let result = ListContinuation.handleReturn(
            in: "1. first",
            cursor: 8
        )
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.text, "1. first\n2. ")
        XCTAssertEqual(result?.selection, NSRange(location: 12, length: 0))
    }

    func testNumberedListIncrementsBeyondTen() {
        let result = ListContinuation.handleReturn(
            in: "10. tenth",
            cursor: 9
        )
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.text, "10. tenth\n11. ")
        XCTAssertEqual(result?.selection, NSRange(location: 14, length: 0))
    }

    func testEmptyNumberedItemTerminatesList() {
        let result = ListContinuation.handleReturn(
            in: "1. first\n2. ",
            cursor: 12
        )
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.text, "1. first\n")
        XCTAssertEqual(result?.selection, NSRange(location: 9, length: 0))
    }

    // MARK: - Task lists

    func testTaskListBulletContinues() {
        let result = ListContinuation.handleReturn(
            in: "- [ ] task one",
            cursor: 14
        )
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.text, "- [ ] task one\n- [ ] ")
        XCTAssertEqual(result?.selection, NSRange(location: 21, length: 0))
    }

    func testCheckedTaskContinuesWithUnchecked() {
        // After a [x] completed item, the new item starts unchecked
        let result = ListContinuation.handleReturn(
            in: "- [x] done",
            cursor: 10
        )
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.text, "- [x] done\n- [ ] ")
        XCTAssertEqual(result?.selection, NSRange(location: 17, length: 0))
    }

    func testEmptyTaskItemTerminates() {
        let result = ListContinuation.handleReturn(
            in: "- [ ] ",
            cursor: 6
        )
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.text, "")
    }

    // MARK: - Indented list items

    func testIndentedBulletContinues() {
        let result = ListContinuation.handleReturn(
            in: "  - nested",
            cursor: 10
        )
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.text, "  - nested\n  - ")
        XCTAssertEqual(result?.selection, NSRange(location: 15, length: 0))
    }

    func testIndentedEmptyBulletTerminates() {
        let result = ListContinuation.handleReturn(
            in: "  - ",
            cursor: 4
        )
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.text, "")
    }

    func testTabIndentedBulletContinues() {
        let result = ListContinuation.handleReturn(
            in: "\t- tabbed",
            cursor: 9
        )
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.text, "\t- tabbed\n\t- ")
    }

    // MARK: - Blockquote

    func testBlockquoteContinues() {
        let result = ListContinuation.handleReturn(
            in: "> quoted",
            cursor: 8
        )
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.text, "> quoted\n> ")
        XCTAssertEqual(result?.selection, NSRange(location: 11, length: 0))
    }

    func testEmptyBlockquoteTerminates() {
        let result = ListContinuation.handleReturn(
            in: "> first\n> ",
            cursor: 10
        )
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.text, "> first\n")
        XCTAssertEqual(result?.selection, NSRange(location: 8, length: 0))
    }

    // MARK: - No list context

    func testReturnInPlainTextReturnsNil() {
        let result = ListContinuation.handleReturn(
            in: "just some text",
            cursor: 14
        )
        XCTAssertNil(result)
    }

    func testReturnInBlankLineReturnsNil() {
        let result = ListContinuation.handleReturn(
            in: "first\n\nsecond",
            cursor: 6
        )
        XCTAssertNil(result)
    }

    func testReturnImmediatelyAfterListReturnsNil() {
        // After list terminated, next return should not auto-continue
        let result = ListContinuation.handleReturn(
            in: "- item\n\n",
            cursor: 8
        )
        XCTAssertNil(result)
    }

    // MARK: - Multiline source — only the current line matters

    func testListContinuesWithUnrelatedTextAbove() {
        let result = ListContinuation.handleReturn(
            in: "Some prose.\n\n- item",
            cursor: 19
        )
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.text, "Some prose.\n\n- item\n- ")
    }
}
