import XCTest
@testable import FolioModel

final class FolioLineSelectionTests: XCTestCase {
    func testStartAndEndAreNormalizedAscending() {
        let s = FolioLineSelection(startLine: 10, endLine: 4, side: .newFile)
        XCTAssertEqual(s.startLine, 4)
        XCTAssertEqual(s.endLine, 10)
    }

    func testContainsBoundaryAndInside() {
        let s = FolioLineSelection(startLine: 5, endLine: 8, side: .newFile)
        XCTAssertTrue(s.contains(5))
        XCTAssertTrue(s.contains(8))
        XCTAssertTrue(s.contains(7))
        XCTAssertFalse(s.contains(4))
        XCTAssertFalse(s.contains(9))
    }

    func testSinglelineSelectionContainsOnlySelf() {
        let s = FolioLineSelection(startLine: 12, endLine: 12, side: .oldFile)
        XCTAssertTrue(s.contains(12))
        XCTAssertFalse(s.contains(11))
        XCTAssertFalse(s.contains(13))
    }

    func testEqualityRespectsSide() {
        let a = FolioLineSelection(startLine: 1, endLine: 3, side: .newFile)
        let b = FolioLineSelection(startLine: 1, endLine: 3, side: .oldFile)
        XCTAssertNotEqual(a, b)
    }
}
