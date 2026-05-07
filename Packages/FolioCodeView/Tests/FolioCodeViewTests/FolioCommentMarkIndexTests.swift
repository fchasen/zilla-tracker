import XCTest
@testable import FolioCodeView
import FolioModel

final class FolioCommentMarkIndexTests: XCTestCase {
    func testIndexesMarksBySideAndLine() {
        let oldMark = FolioCommentMark(id: "old-4", side: .oldFile, line: 4, count: 2)
        let newMark = FolioCommentMark(id: "new-4", side: .newFile, line: 4)
        let index = FolioCommentMarkIndex([oldMark, newMark])

        XCTAssertEqual(index.mark(side: .oldFile, line: 4), oldMark)
        XCTAssertEqual(index.mark(side: .newFile, line: 4), newMark)
        XCTAssertNil(index.mark(side: .oldFile, line: 5))
    }

    func testLastMarkWinsForDuplicateSideAndLine() {
        let first = FolioCommentMark(id: "first", side: .newFile, line: 12)
        let second = FolioCommentMark(id: "second", side: .newFile, line: 12, count: 3)
        let index = FolioCommentMarkIndex([first, second])

        XCTAssertEqual(index.mark(side: .newFile, line: 12), second)
    }
}
