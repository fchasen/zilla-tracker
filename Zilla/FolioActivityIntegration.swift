import Foundation
import PhabricatorKit
import FolioModel

enum FolioActivityIntegration {
    static func anchoredHunk(
        in diff: DiffDetail?,
        path: String,
        line: Int,
        side: AnchorRange.Side
    ) -> DiffHunk? {
        guard let diff else { return nil }
        guard let changeset = diff.changesets.first(where: { $0.currentPath == path }) else {
            return nil
        }
        let anchor = AnchorRange(line: line, length: 1, side: side)
        for hunk in changeset.hunks {
            let parsed = UnifiedDiffParser.parse(
                corpus: hunk.corpus,
                oldStart: hunk.oldOffset,
                newStart: hunk.newOffset
            )
            if parsed.contains(anchor) {
                return parsed
            }
        }
        return nil
    }
}
