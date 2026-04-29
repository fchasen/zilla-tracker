import SwiftUI
import PhabricatorKit
import Textual

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
    let transaction: RevisionTransaction

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            avatar
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(authorName)
                        .font(.callout.weight(.semibold))
                    Text(verbatim: "·")
                        .foregroundStyle(.tertiary)
                    Text(transaction.dateCreated, format: .relative(presentation: .named))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                bodyView
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var avatar: some View {
        let user = transaction.authorPHID.flatMap { workspace.revisionUserDirectory[$0] }
        UserAvatar(
            email: user?.primaryEmail,
            size: 28,
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
            VStack(alignment: .leading, spacing: 4) {
                inlineFileLink(inlineDescriptor)
                if let body = primaryCommentBody, !body.isEmpty {
                    StructuredText(markdown: body)
                        .font(.callout)
                        .textSelection(.enabled)
                }
            }
        } else if let body = primaryCommentBody {
            StructuredText(markdown: body)
                .font(.callout)
                .textSelection(.enabled)
        } else if let caption = activityCaption {
            Text(caption)
                .font(.callout)
                .foregroundStyle(.secondary)
        } else if let type = transaction.type {
            Text(type)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
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
            Text("commented on")
                .font(.caption)
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
