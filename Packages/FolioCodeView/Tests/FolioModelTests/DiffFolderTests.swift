import XCTest
@testable import FolioModel

final class DiffFolderTests: XCTestCase {
    private func ctx(_ n: Int) -> DiffLine {
        DiffLine(kind: .context, oldNumber: n, newNumber: n, text: "ctx\(n)")
    }
    private func add(_ n: Int) -> DiffLine {
        DiffLine(kind: .addition, oldNumber: nil, newNumber: n, text: "add\(n)")
    }
    private func del(_ n: Int) -> DiffLine {
        DiffLine(kind: .deletion, oldNumber: n, newNumber: nil, text: "del\(n)")
    }

    func testEmptyHunkProducesNoSections() {
        let hunk = DiffHunk(oldStart: 0, newStart: 0, lines: [])
        XCTAssertEqual(DiffFolder.fold(hunk).sections, [])
    }

    func testAllContextProducesSingleGap() {
        let hunk = DiffHunk(oldStart: 1, newStart: 1, lines: (1...5).map(ctx))
        XCTAssertEqual(DiffFolder.fold(hunk).sections, [.gap(start: 0, end: 4)])
    }

    func testSingleChangeWithLeadingAndTrailingGaps() {
        var lines: [DiffLine] = (1...10).map(ctx)
        lines[5] = add(6)
        let hunk = DiffHunk(oldStart: 1, newStart: 1, lines: lines)
        let folded = DiffFolder.fold(hunk, contextLines: 2)
        XCTAssertEqual(folded.sections, [
            .gap(start: 0, end: 2),
            .lines(start: 3, end: 7),
            .gap(start: 8, end: 9)
        ])
    }

    func testChangeNearStartHasNoLeadingGap() {
        var lines: [DiffLine] = (1...10).map(ctx)
        lines[1] = add(2)
        let hunk = DiffHunk(oldStart: 1, newStart: 1, lines: lines)
        let folded = DiffFolder.fold(hunk, contextLines: 3)
        XCTAssertEqual(folded.sections, [
            .lines(start: 0, end: 4),
            .gap(start: 5, end: 9)
        ])
    }

    func testChangeNearEndHasNoTrailingGap() {
        var lines: [DiffLine] = (1...10).map(ctx)
        lines[8] = add(9)
        let hunk = DiffHunk(oldStart: 1, newStart: 1, lines: lines)
        let folded = DiffFolder.fold(hunk, contextLines: 3)
        XCTAssertEqual(folded.sections, [
            .gap(start: 0, end: 4),
            .lines(start: 5, end: 9)
        ])
    }

    func testMultipleClustersEachGetTheirOwnContext() {
        var lines: [DiffLine] = (1...20).map(ctx)
        lines[3] = add(4)
        lines[15] = del(16)
        let hunk = DiffHunk(oldStart: 1, newStart: 1, lines: lines)
        let folded = DiffFolder.fold(hunk, contextLines: 2)
        XCTAssertEqual(folded.sections, [
            .lines(start: 1, end: 5),
            .gap(start: 6, end: 12),
            .lines(start: 13, end: 17),
            .gap(start: 18, end: 19)
        ].asPrefixedByLeadingGap())
    }

    func testCloseClustersMergeIntoOneRun() {
        var lines: [DiffLine] = (1...20).map(ctx)
        lines[8] = add(9)
        lines[12] = add(13)
        let hunk = DiffHunk(oldStart: 1, newStart: 1, lines: lines)
        let folded = DiffFolder.fold(hunk, contextLines: 3)
        XCTAssertEqual(folded.sections, [
            .gap(start: 0, end: 4),
            .lines(start: 5, end: 15),
            .gap(start: 16, end: 19)
        ])
    }

    func testAllChangesNoContextProducesSingleLines() {
        let lines: [DiffLine] = (1...4).map(add)
        let hunk = DiffHunk(oldStart: 1, newStart: 1, lines: lines)
        let folded = DiffFolder.fold(hunk, contextLines: 3)
        XCTAssertEqual(folded.sections, [.lines(start: 0, end: 3)])
    }
}

private extension Array where Element == FoldedDiff.Section {
    func asPrefixedByLeadingGap() -> [FoldedDiff.Section] {
        guard let first = first, case let .lines(start, _) = first, start > 0 else { return self }
        return [.gap(start: 0, end: start - 1)] + self
    }
}
