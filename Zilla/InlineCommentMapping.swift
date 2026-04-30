import Foundation
import SwiftUI
import PhabricatorKit
import PierreDiffsSwift

/// In-flight inline composer state. When set, a synthetic editable annotation
/// is injected into the diff at `(path, line)`; submitting it routes to
/// `Workspace.createInlineDraft`.
struct ActiveInlineComposer: Equatable {
    let path: String
    let line: Int
    let length: Int
    let isNewFile: Bool
    let replyTo: String?
    /// Stable id of the synthetic annotation. Used by Pierre to address this
    /// row in submit/cancel callbacks.
    var syntheticID: String {
        "compose-\(path)-\(line)-\(replyTo ?? "")"
    }
}


extension Array where Element == InlineComment {
    /// Groups inline comments into threads on the latest diff, returning one
    /// `DiffAnnotation` per thread (root + replies). Replies appear stacked
    /// inside the parent annotation card.
    /// When `activeComposer` matches `path`, an editable synthetic annotation
    /// is appended (for new comments) or merged into the matching thread (for
    /// replies).
    func diffAnnotations(
        forPath path: String,
        userDirectory: [String: PhabricatorUser],
        currentUserPHID: String?,
        currentUser: PhabricatorUser?,
        latestDiffID: Int,
        activeComposer: ActiveInlineComposer? = nil
    ) -> [DiffAnnotation] {
        let onLatest = filter {
            $0.diffID == latestDiffID && $0.path == path && !$0.isDeleted
        }
        // Drafts are visible only to their author.
        let visible = onLatest.filter { inline in
            inline.transactionPHID != nil || inline.authorPHID == currentUserPHID
        }
        let composer = activeComposer.flatMap { $0.path == path ? $0 : nil }
        if visible.isEmpty && composer == nil { return [] }

        let visiblePHIDs = Set(visible.map(\.phid))
        let byPHID = Dictionary(uniqueKeysWithValues: visible.map { ($0.phid, $0) })
        // A "root" is any visible inline whose `replyToCommentPHID` is nil or
        // whose parent isn't in our visible set (e.g. parent on an older diff).
        let roots = visible.filter { inline in
            guard let parent = inline.replyToCommentPHID else { return true }
            return !visiblePHIDs.contains(parent)
        }

        var threads: [DiffAnnotation] = roots.map { root in
            let thread = Self.collectThread(rootPHID: root.phid, in: byPHID)
            var comments: [AnnotationMetadata.Comment] = thread.map { inline in
                let author = inline.authorPHID.flatMap { userDirectory[$0] }
                let isDraft = inline.transactionPHID == nil
                var subtitleParts: [String] = []
                if let date = inline.dateCreated {
                    subtitleParts.append(Self.relativeDate(date))
                }
                if isDraft {
                    subtitleParts.append("Draft")
                }
                return AnnotationMetadata.Comment(
                    id: inline.phid,
                    author: author?.realName ?? author?.userName ?? "Unknown",
                    body: Remarkup.toCommonMark(inline.content),
                    avatarURL: author?.image?.absoluteString,
                    subtitle: subtitleParts.isEmpty ? nil : subtitleParts.joined(separator: " · ")
                )
            }

            // If the active composer is a reply somewhere in this thread, append
            // an editable comment so it renders inline rather than as its own
            // standalone annotation.
            if let composer, let replyTo = composer.replyTo, thread.contains(where: { $0.phid == replyTo }) {
                comments.append(Self.composerComment(composer, currentUser: currentUser))
            }

            var rootSubtitleParts: [String] = []
            if root.length > 1 {
                rootSubtitleParts.append("Lines \(root.line)–\(root.line + root.length - 1)")
            }
            if root.transactionPHID == nil {
                rootSubtitleParts.append("Draft")
            }
            let rootAuthor = root.authorPHID.flatMap { userDirectory[$0] }
            let side: AnnotationSide = root.isNewFile ? .additions : .deletions

            return DiffAnnotation(
                side: side,
                lineNumber: root.line,
                metadata: AnnotationMetadata(
                    id: root.phid,
                    author: rootAuthor?.realName ?? rootAuthor?.userName ?? "Unknown",
                    body: Remarkup.toCommonMark(root.content),
                    avatarURL: rootAuthor?.image?.absoluteString,
                    subtitle: rootSubtitleParts.isEmpty ? nil : rootSubtitleParts.joined(separator: " · "),
                    comments: comments
                )
            )
        }

        // Standalone composer for a brand-new comment (no replyTo, or replyTo
        // not found in any visible thread).
        if let composer,
           composer.replyTo == nil
            || !threads.contains(where: { annotation in
                annotation.metadata.comments?.contains(where: { $0.id == composer.replyTo }) ?? false
            }) {
            let composerComment = Self.composerComment(composer, currentUser: currentUser)
            let side: AnnotationSide = composer.isNewFile ? .additions : .deletions
            threads.append(
                DiffAnnotation(
                    side: side,
                    lineNumber: composer.line,
                    metadata: AnnotationMetadata(
                        id: composer.syntheticID,
                        author: composerComment.author,
                        body: composerComment.body,
                        avatarURL: composerComment.avatarURL,
                        subtitle: composerComment.subtitle,
                        mode: "compose"
                    )
                )
            )
        }

        return threads
    }

    private static func composerComment(_ composer: ActiveInlineComposer, currentUser: PhabricatorUser?) -> AnnotationMetadata.Comment {
        let author = currentUser?.realName ?? currentUser?.userName ?? "You"
        return AnnotationMetadata.Comment(
            id: composer.syntheticID,
            author: author,
            body: "",
            avatarURL: currentUser?.image?.absoluteString,
            subtitle: composer.replyTo == nil ? "New comment" : "Reply",
            mode: "compose"
        )
    }

    private static func collectThread(rootPHID: String, in byPHID: [String: InlineComment]) -> [InlineComment] {
        guard let root = byPHID[rootPHID] else { return [] }
        var result: [InlineComment] = [root]
        var queue: [String] = [rootPHID]
        while !queue.isEmpty {
            let parent = queue.removeFirst()
            let children = byPHID.values
                .filter { $0.replyToCommentPHID == parent }
                .sorted { ($0.dateCreated ?? .distantPast) < ($1.dateCreated ?? .distantPast) }
            for child in children {
                result.append(child)
                queue.append(child.phid)
            }
        }
        return result
    }

    private static func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: .now)
    }
}
