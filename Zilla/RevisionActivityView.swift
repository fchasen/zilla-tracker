import SwiftUI
import PhabricatorKit
import Textual
import Sliver
import SliverModel
import SliverHighlight

struct RevisionActivityView: View {
    @Environment(Workspace.self) private var workspace

    var body: some View {
        @Bindable var workspace = workspace
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                InspectorSectionHeader(
                    title: "Activity",
                    trailing: visibleTransactions.isEmpty
                        ? nil
                        : "\(visibleTransactions.count)"
                )
                Spacer()
                if hiddenCount > 0 || workspace.activityShowAll {
                    let toggle = Toggle("Show all", isOn: $workspace.activityShowAll)
                        .controlSize(.small)
                        .help(workspace.activityShowAll
                              ? "Hide non-comment activity"
                              : "\(hiddenCount) non-comment item\(hiddenCount == 1 ? "" : "s") hidden")
                    #if os(macOS)
                    toggle.toggleStyle(.checkbox)
                    #else
                    toggle
                    #endif
                }
            }
            if workspace.loadedRevisionTransactions.isEmpty {
                Text("No activity yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if visibleTransactions.isEmpty {
                Text("No comments yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(visibleTransactions, id: \.id) { transaction in
                        ActivityRow(transaction: transaction)
                    }
                }
            }
        }
    }

    private var sortedTransactions: [RevisionTransaction] {
        workspace.loadedRevisionTransactions.sorted { $0.dateCreated < $1.dateCreated }
    }

    private var visibleTransactions: [RevisionTransaction] {
        workspace.activityShowAll
            ? sortedTransactions
            : sortedTransactions.filter(\.isComment)
    }

    private var hiddenCount: Int {
        sortedTransactions.count - sortedTransactions.filter(\.isComment).count
    }
}

struct ActivityRow: View {
    @Environment(Workspace.self) private var workspace
    @Environment(\.colorScheme) private var colorScheme
    let transaction: RevisionTransaction

    var body: some View {
        Group {
            if isCompact {
                compactRow
            } else {
                expandedRow
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var expandedRow: some View {
        HStack(alignment: .top, spacing: 12) {
            avatar(size: 28)
            VStack(alignment: .leading, spacing: 4) {
                headerLine
                bodyView
            }
            Spacer(minLength: 0)
        }
    }

    private var compactRow: some View {
        HStack(alignment: .center, spacing: 8) {
            avatar(size: 22)
            headerLine
            if hasInlineCaption {
                Text(verbatim: "·")
                    .foregroundStyle(.tertiary)
                inlineCaptionView
            }
            Spacer(minLength: 0)
        }
    }

    private var headerLine: some View {
        HStack(spacing: 6) {
            Text(authorName)
                .font(.callout.weight(.semibold))
            Text(verbatim: "·")
                .foregroundStyle(.tertiary)
            Text(transaction.dateCreated, format: .relative(presentation: .named))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var isCompact: Bool {
        primaryCommentBody == nil && !isInline
    }

    private var hasInlineCaption: Bool {
        activityCaption != nil || transaction.type != nil
    }

    @ViewBuilder
    private var inlineCaptionView: some View {
        if let caption = activityCaption {
            Text(caption)
                .font(.callout)
                .foregroundStyle(.secondary)
        } else if let type = transaction.type {
            Text(type)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private func avatar(size: CGFloat) -> some View {
        let user = transaction.authorPHID.flatMap { workspace.revisionUserDirectory[$0] }
        UserAvatar(
            email: user?.primaryEmail,
            size: size,
            imageURL: user?.image
        )
    }

    private var authorName: String {
        if let phid = transaction.authorPHID,
           let user = workspace.revisionUserDirectory[phid] {
            return user.realName ?? user.userName
        }
        return "Someone"
    }

    @ViewBuilder
    private var bodyView: some View {
        if isInline, let inlineDescriptor {
            VStack(alignment: .leading, spacing: 6) {
                if isThreadHead, let hunk = anchoredHunk(for: inlineDescriptor) {
                    SliverView(
                        path: inlineDescriptor.path,
                        hunk: hunk,
                        anchor: AnchorRange(
                            line: inlineDescriptor.line,
                            length: max(1, (transaction.fields.length ?? 0) + 1),
                            side: (transaction.fields.isNewFile ?? true) ? .newFile : .oldFile
                        ),
                        isOutdated: isOutdatedAgainstLatestDiff,
                        theme: colorScheme == .dark ? .dark : .light,
                        onPathTap: { workspace.revealChangeset(path: inlineDescriptor.path) }
                    )
                } else {
                    inlineFileLink(inlineDescriptor)
                }
                if let body = primaryCommentBody, !body.isEmpty {
                    RemarkupText(source: body)
                        .font(.callout)
                        .textSelection(.enabled)
                }
            }
        } else if let body = primaryCommentBody {
            RemarkupText(source: body)
                .font(.callout)
                .textSelection(.enabled)
        }
    }

    private var isThreadHead: Bool {
        transaction.fields.replyToCommentPHID == nil
    }

    private var isOutdatedAgainstLatestDiff: Bool {
        guard let txDiffID = transaction.fields.diffID,
              let loadedID = workspace.loadedRevisionDiff?.id else {
            return false
        }
        return txDiffID != loadedID
    }

    private func anchoredHunk(for descriptor: InlineDescriptor) -> DiffHunk? {
        SliverActivityIntegration.anchoredHunk(
            in: workspace.loadedRevisionDiff,
            path: descriptor.path,
            line: descriptor.line,
            side: (transaction.fields.isNewFile ?? true) ? .newFile : .oldFile
        )
    }

    private var isInline: Bool {
        transaction.fields.path != nil && transaction.fields.line != nil
    }

    private struct InlineDescriptor {
        let path: String
        let line: Int
    }

    private var inlineDescriptor: InlineDescriptor? {
        guard let path = transaction.fields.path,
              let line = transaction.fields.line else { return nil }
        return InlineDescriptor(path: path, line: line)
    }

    @ViewBuilder
    private func inlineFileLink(_ descriptor: InlineDescriptor) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "text.bubble")
                .font(.caption2)
                .foregroundStyle(.secondary)
            let jumpButton = Button {
                workspace.revealChangeset(path: descriptor.path)
            } label: {
                Text("\(descriptor.path):\(descriptor.line)")
                    .font(.callout.monospaced())
                    .foregroundStyle(.tint)
                    .underline(true, color: .clear)
            }
            .buttonStyle(.plain)
            .help("Jump to \(descriptor.path):\(descriptor.line)")
            #if os(macOS)
            jumpButton.pointerStyle(.link)
            #else
            jumpButton
            #endif
        }
    }

    private var primaryCommentBody: String? {
        switch transaction.type {
        case "comment", "inline":
            return transaction.comments.last(where: { ($0.removed ?? false) == false })?.content.raw
        default:
            // Some Phabricator forks report different inline transaction
            // type strings; fall back to the comment body when fields suggest
            // an inline anchor.
            if isInline {
                return transaction.comments.last(where: { ($0.removed ?? false) == false })?.content.raw
            }
            return nil
        }
    }

    private var activityCaption: String? {
        switch transaction.type {
        case "accept": return "accepted this revision"
        case "reject", "request-changes": return "requested changes"
        case "abandon": return "abandoned this revision"
        case "reclaim": return "reclaimed this revision"
        case "reopen": return "reopened this revision"
        case "close": return "closed this revision"
        case "plan-changes": return "planned changes"
        case "request-review": return "requested review"
        case "resign": return "resigned as a reviewer"
        case "update": return "uploaded a new diff"
        case "reviewers.set", "reviewers.add": return "updated reviewers"
        case "status": return "changed status"
        case "title": return "edited the title"
        case "summary": return "edited the summary"
        case "subscribers.add", "subscribers.set": return "updated subscribers"
        case "projects.add", "projects.set": return "updated projects"
        case "create": return "created this revision"
        default: return nil
        }
    }
}
