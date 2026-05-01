import XCTest
@testable import FolioModel

final class SplitRowBuilderTests: XCTestCase {
    func testEmptyInputProducesNoRows() {
        XCTAssertEqual(SplitRowBuilder.build([]), [])
    }

    func testContextOnlyMirrorsBothSides() {
        let lines = [
            DiffLine(kind: .context, oldNumber: 1, newNumber: 1, text: "a"),
            DiffLine(kind: .context, oldNumber: 2, newNumber: 2, text: "b")
        ]
        let rows = SplitRowBuilder.build(lines)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].left?.text, "a")
        XCTAssertEqual(rows[0].right?.text, "a")
        XCTAssertEqual(rows[1].left?.text, "b")
        XCTAssertEqual(rows[1].right?.text, "b")
    }

    func testBalancedDeleteAddPairUpRowwise() {
        let lines = [
            DiffLine(kind: .deletion, oldNumber: 5, newNumber: nil, text: "old1"),
            DiffLine(kind: .deletion, oldNumber: 6, newNumber: nil, text: "old2"),
            DiffLine(kind: .addition, oldNumber: nil, newNumber: 5, text: "new1"),
            DiffLine(kind: .addition, oldNumber: nil, newNumber: 6, text: "new2")
        ]
        let rows = SplitRowBuilder.build(lines)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].left?.text, "old1")
        XCTAssertEqual(rows[0].right?.text, "new1")
        XCTAssertEqual(rows[1].left?.text, "old2")
        XCTAssertEqual(rows[1].right?.text, "new2")
    }

    func testSurplusDeletionsLeavePhantomRight() {
        let lines = [
            DiffLine(kind: .deletion, oldNumber: 5, newNumber: nil, text: "d1"),
            DiffLine(kind: .deletion, oldNumber: 6, newNumber: nil, text: "d2"),
            DiffLine(kind: .deletion, oldNumber: 7, newNumber: nil, text: "d3"),
            DiffLine(kind: .addition, oldNumber: nil, newNumber: 5, text: "a1")
        ]
        let rows = SplitRowBuilder.build(lines)
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[0].right?.text, "a1")
        XCTAssertNil(rows[1].right)
        XCTAssertNil(rows[2].right)
        XCTAssertEqual(rows[1].left?.text, "d2")
        XCTAssertEqual(rows[2].left?.text, "d3")
    }

    func testSurplusAdditionsLeavePhantomLeft() {
        let lines = [
            DiffLine(kind: .deletion, oldNumber: 5, newNumber: nil, text: "d1"),
            DiffLine(kind: .addition, oldNumber: nil, newNumber: 5, text: "a1"),
            DiffLine(kind: .addition, oldNumber: nil, newNumber: 6, text: "a2"),
            DiffLine(kind: .addition, oldNumber: nil, newNumber: 7, text: "a3")
        ]
        let rows = SplitRowBuilder.build(lines)
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[0].left?.text, "d1")
        XCTAssertNil(rows[1].left)
        XCTAssertNil(rows[2].left)
        XCTAssertEqual(rows[1].right?.text, "a2")
        XCTAssertEqual(rows[2].right?.text, "a3")
    }

    func testContextFlushesPendingRunsBefore() {
        let lines = [
            DiffLine(kind: .deletion, oldNumber: 1, newNumber: nil, text: "d"),
            DiffLine(kind: .addition, oldNumber: nil, newNumber: 1, text: "a"),
            DiffLine(kind: .context, oldNumber: 2, newNumber: 2, text: "c")
        ]
        let rows = SplitRowBuilder.build(lines)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].left?.text, "d")
        XCTAssertEqual(rows[0].right?.text, "a")
        XCTAssertEqual(rows[1].left?.text, "c")
        XCTAssertEqual(rows[1].right?.text, "c")
    }

    func testMultipleRunsSeparatedByContext() {
        let lines = [
            DiffLine(kind: .deletion, oldNumber: 1, newNumber: nil, text: "d1"),
            DiffLine(kind: .addition, oldNumber: nil, newNumber: 1, text: "a1"),
            DiffLine(kind: .context, oldNumber: 2, newNumber: 2, text: "c"),
            DiffLine(kind: .deletion, oldNumber: 3, newNumber: nil, text: "d2"),
            DiffLine(kind: .addition, oldNumber: nil, newNumber: 3, text: "a2")
        ]
        let rows = SplitRowBuilder.build(lines)
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[0].left?.text, "d1")
        XCTAssertEqual(rows[0].right?.text, "a1")
        XCTAssertEqual(rows[1].left?.text, "c")
        XCTAssertEqual(rows[1].right?.text, "c")
        XCTAssertEqual(rows[2].left?.text, "d2")
        XCTAssertEqual(rows[2].right?.text, "a2")
    }

    func testPureDeletionsHaveAllPhantomRight() {
        let lines = [
            DiffLine(kind: .deletion, oldNumber: 1, newNumber: nil, text: "d1"),
            DiffLine(kind: .deletion, oldNumber: 2, newNumber: nil, text: "d2")
        ]
        let rows = SplitRowBuilder.build(lines)
        XCTAssertEqual(rows.count, 2)
        XCTAssertNil(rows[0].right)
        XCTAssertNil(rows[1].right)
    }

    func testNoNewlineFlushesAndMirrors() {
        let lines = [
            DiffLine(kind: .deletion, oldNumber: 1, newNumber: nil, text: "d"),
            DiffLine(kind: .noNewline, oldNumber: nil, newNumber: nil, text: " No newline at end of file")
        ]
        let rows = SplitRowBuilder.build(lines)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].left?.text, "d")
        XCTAssertNil(rows[0].right)
        XCTAssertEqual(rows[1].left?.kind, .noNewline)
        XCTAssertEqual(rows[1].right?.kind, .noNewline)
    }
}
