import Foundation
import MarkdownEditorKit

/// The conventional-comment labels Mozilla reviewers attach to Phabricator
/// comments, matching what the `phab-conventional-comments` browser extension
/// inserts: a one-segment remarkup `{nav}` breadcrumb carrying a FontAwesome
/// icon name and the label text.
///
/// The extension prefixes `issue:` with `(IMPORTANT)`. Zilla doesn't:
/// `Remarkup.rewriteCallout` turns that into a bare `>` blockquote and
/// `Markdown.toRemarkup` has no rule back, so emitting it would quietly
/// downgrade the callout the next time the comment is edited.
nonisolated enum CommentLabels {
    struct Label: Hashable, Sendable, Identifiable {
        let name: String
        let icon: String

        var id: String { name }
        var systemImage: String { PhabricatorIcons.systemImage(for: icon) }
    }

    static let all: [Label] = [
        Label(name: "praise:", icon: "thumbs-up"),
        Label(name: "nitpick:", icon: "info-circle"),
        Label(name: "suggestion:", icon: "pencil"),
        Label(name: "issue:", icon: "exclamation-triangle"),
        Label(name: "question:", icon: "question-circle"),
        Label(name: "thought:", icon: "comment"),
        Label(name: "note:", icon: "sticky-note"),
        Label(name: "typo:", icon: "keyboard-o"),
        Label(name: "follow-up:", icon: "share")
    ]

    /// Tolerates every spelling Phabricator accepts after the keyword — a
    /// space, a comma, or the extension's `,` plus two spaces.
    static let tokenPattern = #"\{nav(?:\s+|\s*,\s*)icon=([A-Za-z0-9_\-]+)\s*,\s*name=([^}\n]*)\}"#

    /// The `{nav}` token to insert for `label`, trailing space included so the
    /// comment body starts right after it.
    static func insertionText(for label: Label) -> String {
        "{nav, icon=\(label.icon), name=\(label.name)} "
    }

    /// Matches `insertionText(for:)` and the extension's own spelling, so
    /// picking a second label replaces the first instead of stacking.
    static let leadingTokenPattern = "^" + tokenPattern + #"[ \t]*"#

    static func parse(_ token: String) -> (icon: String, name: String)? {
        guard let regex = try? NSRegularExpression(pattern: "^" + tokenPattern + "$") else { return nil }
        let ns = token as NSString
        guard let match = regex.firstMatch(in: token, range: NSRange(location: 0, length: ns.length)),
              match.range(at: 1).location != NSNotFound,
              match.range(at: 2).location != NSNotFound
        else { return nil }
        let icon = ns.substring(with: match.range(at: 1))
        let name = ns.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespaces)
        guard !icon.isEmpty else { return nil }
        return (icon, name)
    }

    /// Every `{nav}` comment-label token in `text`, in document order, as
    /// UTF-16 ranges.
    static func matches(in text: String) -> [(range: NSRange, icon: String, name: String)] {
        guard let regex = try? NSRegularExpression(pattern: tokenPattern) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
            .compactMap { match in
                guard match.range(at: 1).location != NSNotFound,
                      match.range(at: 2).location != NSNotFound
                else { return nil }
                let icon = ns.substring(with: match.range(at: 1))
                guard !icon.isEmpty else { return nil }
                let name = ns.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespaces)
                return (match.range, icon, name)
            }
    }

    /// The label whose text `name` is, if it is one of the nine. Used for the
    /// tooltip; an unrecognised name still renders, with its own text.
    static func label(named name: String) -> Label? {
        all.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    // MARK: - editor

    static let inlineContentKind = "zilla.commentLabel"

    /// Collapses the token to a bare icon in the composer. The rule stores the
    /// matched source verbatim, so an edited comment reposts byte-identical —
    /// the extension's double space included.
    static let proseRules: [InlineContentRule] = [
        InlineContentRule(id: inlineContentKind, pattern: tokenPattern) { match in
            guard let icon = match.capture(1), !icon.isEmpty else { return nil }
            let name = (match.capture(2) ?? "").trimmingCharacters(in: .whitespaces)
            return .custom(
                kind: inlineContentKind,
                label: name,
                systemImage: PhabricatorIcons.systemImage(for: icon)
            )
        }
    ]
}
