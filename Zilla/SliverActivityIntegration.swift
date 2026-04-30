import Foundation
import PhabricatorKit
import SliverModel

enum SliverActivityIntegration {
    static func anchoredHunk(
        in diff: DiffDetail?,
        path: String,
        line: Int,
        side: AnchorRange.Side
    ) -> DiffHunk? {
        guard let diff,
              let changeset = diff.changesets.first(where: { $0.currentPath == path }) else {
            return nil
        }
        for hunk in changeset.hunks {
            if covers(hunk: hunk, line: line, side: side) {
                return UnifiedDiffParser.parse(
                    corpus: hunk.corpus,
                    oldStart: hunk.oldOffset,
                    newStart: hunk.newOffset
                )
            }
        }
        return nil
    }

    private static func covers(hunk: Hunk, line: Int, side: AnchorRange.Side) -> Bool {
        switch side {
        case .newFile:
            return line >= hunk.newOffset && line < hunk.newOffset + max(hunk.newLen, 1)
        case .oldFile:
            return line >= hunk.oldOffset && line < hunk.oldOffset + max(hunk.oldLen, 1)
        }
    }
}
