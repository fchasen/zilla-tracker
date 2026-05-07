import XCTest
@testable import FolioModel

final class IntralineDiffTests: XCTestCase {
    func testIdenticalStringsHaveNoRanges() {
        let r = IntralineDiff.compute(old: "hello", new: "hello")
        XCTAssertTrue(r.isEmpty)
    }

    func testEmptyStrings() {
        let r = IntralineDiff.compute(old: "", new: "")
        XCTAssertTrue(r.isEmpty)
    }

    func testPureInsertionAtEnd() {
        let r = IntralineDiff.compute(old: "phase:boot", new: "phase:boot-ready")
        XCTAssertEqual(r.oldRanges, [])
        XCTAssertEqual(r.newRanges, [NSRange(location: 10, length: 6)])
    }

    func testPureRemovalAtEnd() {
        let r = IntralineDiff.compute(old: "phase:boot-ready", new: "phase:boot")
        XCTAssertEqual(r.oldRanges, [NSRange(location: 10, length: 6)])
        XCTAssertEqual(r.newRanges, [])
    }

    func testInsertionAtStart() {
        let r = IntralineDiff.compute(old: "world", new: "hello world")
        XCTAssertEqual(r.oldRanges, [])
        XCTAssertEqual(r.newRanges, [NSRange(location: 0, length: 6)])
    }

    func testReplacementInMiddle() {
        let r = IntralineDiff.compute(old: "phase:mid", new: "phase:end")
        XCTAssertEqual(r.oldRanges, [NSRange(location: 6, length: 3)])
        XCTAssertEqual(r.newRanges, [NSRange(location: 6, length: 3)])
    }

    func testWordBoundaryNotPerCharacter() {
        let r = IntralineDiff.compute(old: "let foo = 1", new: "let bar = 2")
        XCTAssertEqual(r.oldRanges, [
            NSRange(location: 4, length: 3),
            NSRange(location: 10, length: 1)
        ])
        XCTAssertEqual(r.newRanges, [
            NSRange(location: 4, length: 3),
            NSRange(location: 10, length: 1)
        ])
    }

    func testIdentifierTreatedAsSingleToken() {
        let r = IntralineDiff.compute(old: "callFoo(x)", new: "callBar(x)")
        XCTAssertEqual(r.oldRanges, [NSRange(location: 0, length: 7)])
        XCTAssertEqual(r.newRanges, [NSRange(location: 0, length: 7)])
    }

    func testNonASCIIWordUsesUTF16Ranges() {
        let r = IntralineDiff.compute(old: "let café = 1", new: "let cafe = 1")
        XCTAssertEqual(r.oldRanges, [NSRange(location: 4, length: 4)])
        XCTAssertEqual(r.newRanges, [NSRange(location: 4, length: 4)])
    }

    func testWhitespaceCollapsesIntoSingleToken() {
        let r = IntralineDiff.compute(old: "a  b", new: "a   b")
        XCTAssertEqual(r.oldRanges, [NSRange(location: 1, length: 2)])
        XCTAssertEqual(r.newRanges, [NSRange(location: 1, length: 3)])
    }

    func testInsertionPlusReplacement() {
        let r = IntralineDiff.compute(old: "phase:mid", new: "phase:mid-${x}")
        XCTAssertEqual(r.oldRanges, [])
        XCTAssertEqual(r.newRanges, [NSRange(location: 9, length: 5)])
    }

    func testCompletelyDifferentLines() {
        let r = IntralineDiff.compute(old: "summary.push('phase:tail');", new: "if (tasks.length > 0) {")
        XCTAssertFalse(r.oldRanges.isEmpty)
        XCTAssertFalse(r.newRanges.isEmpty)
    }

    func testRangesAreSortedAndNonOverlapping() {
        let r = IntralineDiff.compute(old: "abcXdefYghi", new: "abc1def2ghi")
        for ranges in [r.oldRanges, r.newRanges] {
            for i in 1..<ranges.count {
                XCTAssertGreaterThan(
                    ranges[i].location,
                    ranges[i - 1].location + ranges[i - 1].length - 1
                )
            }
        }
    }
}
