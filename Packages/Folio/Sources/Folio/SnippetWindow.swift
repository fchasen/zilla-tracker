import Foundation
import FolioModel

struct SnippetBounds {
    let startIndex: Int
    let endIndex: Int
    let totalCount: Int

    var isEmpty: Bool { totalCount == 0 || endIndex < startIndex }
    var linesAbove: Int { startIndex }
    var linesBelow: Int { max(0, totalCount - endIndex - 1) }
}

enum SnippetWindow {
    static func slice(hunk: DiffHunk, anchor: AnchorRange, contextLines: Int) -> ArraySlice<DiffLine> {
        slice(hunk: hunk, anchor: anchor, contextAbove: contextLines, contextBelow: contextLines)
    }

    static func slice(
        hunk: DiffHunk,
        anchor: AnchorRange,
        contextAbove: Int,
        contextBelow: Int
    ) -> ArraySlice<DiffLine> {
        let b = bounds(hunk: hunk, anchor: anchor, contextAbove: contextAbove, contextBelow: contextBelow)
        if b.isEmpty { return ArraySlice(hunk.lines) }
        return hunk.lines[b.startIndex...b.endIndex]
    }

    static func bounds(
        hunk: DiffHunk,
        anchor: AnchorRange,
        contextAbove: Int,
        contextBelow: Int
    ) -> SnippetBounds {
        let total = hunk.lines.count
        guard total > 0 else {
            return SnippetBounds(startIndex: 0, endIndex: -1, totalCount: 0)
        }
        guard let anchorIndex = hunk.indexOfFirstLine(matching: anchor) else {
            return SnippetBounds(startIndex: 0, endIndex: total - 1, totalCount: total)
        }
        let lastAnchorIndex = lastIndex(forAnchor: anchor, in: hunk, startingAt: anchorIndex)
        let start = max(0, anchorIndex - contextAbove)
        let end = min(total - 1, lastAnchorIndex + contextBelow)
        return SnippetBounds(startIndex: start, endIndex: end, totalCount: total)
    }

    private static func lastIndex(forAnchor anchor: AnchorRange, in hunk: DiffHunk, startingAt firstIndex: Int) -> Int {
        guard anchor.length > 1 else { return firstIndex }
        let endLine = anchor.line + anchor.length - 1
        for i in firstIndex..<hunk.lines.count {
            let line = hunk.lines[i]
            switch anchor.side {
            case .newFile:
                if let n = line.newNumber, n >= endLine { return i }
            case .oldFile:
                if let n = line.oldNumber, n >= endLine { return i }
            }
        }
        return hunk.lines.count - 1
    }
}
