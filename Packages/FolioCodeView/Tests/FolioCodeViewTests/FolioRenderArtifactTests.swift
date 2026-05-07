import XCTest
@testable import FolioCodeView
import FolioHighlight
import FolioModel

final class FolioRenderArtifactTests: XCTestCase {
    func testDiffArtifactIndexesRunsByLine() {
        let hunk = DiffHunk(
            oldStart: 1,
            newStart: 1,
            lines: [
                DiffLine(kind: .context, oldNumber: 1, newNumber: 1, text: "let first = 1;"),
                DiffLine(kind: .addition, oldNumber: nil, newNumber: 2, text: "const second = 2;")
            ]
        )

        let artifact = FolioRenderArtifactBuilder.full(
            content: .diff(hunk, anchor: nil, mode: .unified),
            marks: [],
            contextLines: 3,
            path: "example.js",
            theme: .light
        )

        guard case let .diff(diff) = artifact.kind else {
            return XCTFail("Expected diff artifact")
        }

        XCTAssertFalse(artifact.runs.isEmpty)
        XCTAssertEqual(diff.runsByLine.count, diff.lineRanges.count)
        XCTAssertFalse(diff.runsByLine[0].isEmpty)
        XCTAssertFalse(diff.runsByLine[1].isEmpty)
        assertRunsIntersectTheirLines(runsByLine: diff.runsByLine, lineRanges: diff.lineRanges)
    }

    func testCodeArtifactIndexesRunsByLine() {
        let artifact = FolioRenderArtifactBuilder.full(
            content: .code("let first = 1;\nconst second = 2;", startLine: 10),
            marks: [],
            contextLines: 3,
            path: "example.js",
            theme: .light
        )

        guard case let .code(code) = artifact.kind else {
            return XCTFail("Expected code artifact")
        }

        XCTAssertFalse(artifact.runs.isEmpty)
        XCTAssertEqual(code.runsByLine.count, code.lineRanges.count)
        XCTAssertFalse(code.runsByLine[0].isEmpty)
        XCTAssertFalse(code.runsByLine[1].isEmpty)
        assertRunsIntersectTheirLines(runsByLine: code.runsByLine, lineRanges: code.lineRanges)
    }

    func testSkeletonCreatesEmptyRunSlots() {
        let hunk = DiffHunk(
            oldStart: 1,
            newStart: 1,
            lines: [
                DiffLine(kind: .context, oldNumber: 1, newNumber: 1, text: "let first = 1;"),
                DiffLine(kind: .addition, oldNumber: nil, newNumber: 2, text: "const second = 2;")
            ]
        )

        let artifact = FolioRenderArtifactBuilder.skeleton(
            content: .diff(hunk, anchor: nil, mode: .unified),
            marks: [],
            contextLines: 3
        )

        guard case let .diff(diff) = artifact.kind else {
            return XCTFail("Expected diff artifact")
        }

        XCTAssertEqual(diff.runsByLine.count, diff.lineRanges.count)
        XCTAssertTrue(diff.runsByLine.allSatisfy(\.isEmpty))
    }

    func testLargeCodeArtifactSkipsHighlightRuns() {
        let text = String(repeating: "let value = 1;\n", count: FolioRenderArtifactBuilder.highlightUTF16Limit / 14 + 1)
        let artifact = FolioRenderArtifactBuilder.full(
            content: .code(text, startLine: 1),
            marks: [],
            contextLines: 3,
            path: "large.js",
            theme: .light
        )

        guard case let .code(code) = artifact.kind else {
            return XCTFail("Expected code artifact")
        }

        XCTAssertTrue(artifact.runs.isEmpty)
        XCTAssertEqual(code.runsByLine.count, code.lineRanges.count)
        XCTAssertTrue(code.runsByLine.allSatisfy(\.isEmpty))
    }

    func testLargeDiffArtifactSkipsHighlightRuns() {
        let line = String(repeating: "x", count: FolioRenderArtifactBuilder.highlightUTF16Limit + 1)
        let hunk = DiffHunk(
            oldStart: 1,
            newStart: 1,
            lines: [
                DiffLine(kind: .addition, oldNumber: nil, newNumber: 1, text: line)
            ]
        )

        let artifact = FolioRenderArtifactBuilder.full(
            content: .diff(hunk, anchor: nil, mode: .unified),
            marks: [],
            contextLines: 3,
            path: "large.js",
            theme: .light
        )

        guard case let .diff(diff) = artifact.kind else {
            return XCTFail("Expected diff artifact")
        }

        XCTAssertTrue(artifact.runs.isEmpty)
        XCTAssertEqual(diff.runsByLine.count, diff.lineRanges.count)
        XCTAssertTrue(diff.runsByLine.allSatisfy(\.isEmpty))
    }

    private func assertRunsIntersectTheirLines(
        runsByLine: [[FolioHighlighter.Run]],
        lineRanges: [NSRange],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for (index, runs) in runsByLine.enumerated() {
            for run in runs {
                XCTAssertGreaterThan(
                    NSIntersectionRange(run.range, lineRanges[index]).length,
                    0,
                    file: file,
                    line: line
                )
            }
        }
    }
}
