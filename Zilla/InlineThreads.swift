import Foundation
import PhabricatorKit

nonisolated enum InlineThreads {
    private struct Anchor: Hashable {
        let isNewFile: Bool
        let line: Int
    }

    static func group(_ visible: [InlineComment]) -> [String: [InlineComment]] {
        let visiblePHIDs = Set(visible.map(\.phid))
        var childrenByParent: [String: [InlineComment]] = [:]
        var roots: [InlineComment] = []
        for inline in visible {
            if let parent = inline.replyToCommentPHID, visiblePHIDs.contains(parent) {
                childrenByParent[parent, default: []].append(inline)
            } else {
                roots.append(inline)
            }
        }

        var anchors: [Anchor] = []
        var rootsByAnchor: [Anchor: [InlineComment]] = [:]
        for root in roots.sorted(by: chronological) {
            let anchor = Anchor(isNewFile: root.isNewFile, line: root.line)
            if rootsByAnchor[anchor] == nil {
                anchors.append(anchor)
            }
            rootsByAnchor[anchor, default: []].append(root)
        }

        var result: [String: [InlineComment]] = [:]
        for anchor in anchors {
            guard let group = rootsByAnchor[anchor], let first = group.first else { continue }
            var collected: [InlineComment] = []
            for root in group {
                appendSubtree(of: root, childrenByParent: childrenByParent, into: &collected)
            }
            result[first.phid] = collected
        }
        return result
    }

    private static func appendSubtree(
        of comment: InlineComment,
        childrenByParent: [String: [InlineComment]],
        into collected: inout [InlineComment]
    ) {
        collected.append(comment)
        for child in (childrenByParent[comment.phid] ?? []).sorted(by: chronological) {
            appendSubtree(of: child, childrenByParent: childrenByParent, into: &collected)
        }
    }

    private static func chronological(_ lhs: InlineComment, _ rhs: InlineComment) -> Bool {
        let lhsDate = lhs.dateCreated ?? .distantPast
        let rhsDate = rhs.dateCreated ?? .distantPast
        if lhsDate != rhsDate { return lhsDate < rhsDate }
        return lhs.id < rhs.id
    }
}
