import Foundation
import SliverModel

enum SnippetWindow {
    static func slice(hunk: DiffHunk, anchor: AnchorRange, contextLines: Int) -> ArraySlice<DiffLine> {
        guard !hunk.lines.isEmpty,
              let anchorIndex = hunk.indexOfFirstLine(matching: anchor) else {
            return ArraySlice(hunk.lines)
        }
        let lastAnchorIndex = lastIndex(forAnchor: anchor, in: hunk, startingAt: anchorIndex)
        let start = max(0, anchorIndex - contextLines)
        let end = min(hunk.lines.count - 1, lastAnchorIndex)
        return hunk.lines[start...end]
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
