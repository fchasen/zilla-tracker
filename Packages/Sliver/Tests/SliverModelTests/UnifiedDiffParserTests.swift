import XCTest
@testable import SliverModel

final class UnifiedDiffParserTests: XCTestCase {
    func testEmptyCorpusProducesNoLines() {
        let hunk = UnifiedDiffParser.parse(corpus: "", oldStart: 1, newStart: 1)
        XCTAssertEqual(hunk.lines, [])
        XCTAssertEqual(hunk.oldStart, 1)
        XCTAssertEqual(hunk.newStart, 1)
    }

    func testContextLinesNumberBothSides() {
        let corpus = " line A\n line B\n"
        let hunk = UnifiedDiffParser.parse(corpus: corpus, oldStart: 10, newStart: 20)
        XCTAssertEqual(hunk.lines.count, 2)
        XCTAssertEqual(hunk.lines[0], DiffLine(kind: .context, oldNumber: 10, newNumber: 20, text: "line A"))
        XCTAssertEqual(hunk.lines[1], DiffLine(kind: .context, oldNumber: 11, newNumber: 21, text: "line B"))
    }

    func testDeletionAdvancesOldOnly() {
        let corpus = " keep\n-gone\n keep2\n"
        let hunk = UnifiedDiffParser.parse(corpus: corpus, oldStart: 5, newStart: 5)
        XCTAssertEqual(hunk.lines.map(\.kind), [.context, .deletion, .context])
        XCTAssertEqual(hunk.lines[0].oldNumber, 5)
        XCTAssertEqual(hunk.lines[0].newNumber, 5)
        XCTAssertEqual(hunk.lines[1].oldNumber, 6)
        XCTAssertNil(hunk.lines[1].newNumber)
        XCTAssertEqual(hunk.lines[2].oldNumber, 7)
        XCTAssertEqual(hunk.lines[2].newNumber, 6)
    }

    func testAdditionAdvancesNewOnly() {
        let corpus = " keep\n+added\n keep2\n"
        let hunk = UnifiedDiffParser.parse(corpus: corpus, oldStart: 5, newStart: 5)
        XCTAssertEqual(hunk.lines.map(\.kind), [.context, .addition, .context])
        XCTAssertNil(hunk.lines[1].oldNumber)
        XCTAssertEqual(hunk.lines[1].newNumber, 6)
        XCTAssertEqual(hunk.lines[2].oldNumber, 6)
        XCTAssertEqual(hunk.lines[2].newNumber, 7)
    }

    func testReplacementHunk() {
        let corpus = """
         var propertyPattern =
        -    /\\s*(article|dc)/
        +    /\\s*(article|dc|og:image)/

        """
        let hunk = UnifiedDiffParser.parse(corpus: corpus, oldStart: 100, newStart: 100)
        XCTAssertEqual(hunk.lines.map(\.kind), [.context, .deletion, .addition])
        XCTAssertEqual(hunk.lines[0].text, "var propertyPattern =")
        XCTAssertEqual(hunk.lines[1].text, "    /\\s*(article|dc)/")
        XCTAssertEqual(hunk.lines[2].text, "    /\\s*(article|dc|og:image)/")
        XCTAssertEqual(hunk.lines[1].oldNumber, 101)
        XCTAssertEqual(hunk.lines[2].newNumber, 101)
    }

    func testNoNewlineMarkerDoesNotAdvanceCounters() {
        let corpus = " a\n-b\n\\ No newline at end of file\n"
        let hunk = UnifiedDiffParser.parse(corpus: corpus, oldStart: 1, newStart: 1)
        XCTAssertEqual(hunk.lines.map(\.kind), [.context, .deletion, .noNewline])
        XCTAssertNil(hunk.lines[2].oldNumber)
        XCTAssertNil(hunk.lines[2].newNumber)
    }

    func testIndexOfFirstLineByNewSide() {
        let corpus = " keep\n+added\n+added2\n"
        let hunk = UnifiedDiffParser.parse(corpus: corpus, oldStart: 1, newStart: 1)
        let anchor = AnchorRange(line: 3, length: 1, side: .newFile)
        XCTAssertEqual(hunk.indexOfFirstLine(matching: anchor), 2)
    }

    func testIndexOfFirstLineByOldSide() {
        let corpus = " keep\n-gone\n keep2\n"
        let hunk = UnifiedDiffParser.parse(corpus: corpus, oldStart: 10, newStart: 10)
        let anchor = AnchorRange(line: 11, length: 1, side: .oldFile)
        XCTAssertEqual(hunk.indexOfFirstLine(matching: anchor), 1)
    }
}
