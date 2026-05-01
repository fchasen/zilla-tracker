import SwiftUI
import PhabricatorKit
import Marginalia

struct InlineThreadView: View {
    let thread: [InlineComment]
    let userDirectory: [String: PhabricatorUser]
    let currentUserPHID: String?
    let onReply: () -> Void
    let onEditDraft: (InlineComment) -> Void
    let onDeleteDraft: (InlineComment) -> Void
    let composerContent: (() -> AnyView)?

    init(
        thread: [InlineComment],
        userDirectory: [String: PhabricatorUser],
        currentUserPHID: String?,
        onReply: @escaping () -> Void,
        onEditDraft: @escaping (InlineComment) -> Void,
        onDeleteDraft: @escaping (InlineComment) -> Void,
        composerContent: (() -> AnyView)? = nil
    ) {
        self.thread = thread
        self.userDirectory = userDirectory
        self.currentUserPHID = currentUserPHID
        self.onReply = onReply
        self.onEditDraft = onEditDraft
        self.onDeleteDraft = onDeleteDraft
        self.composerContent = composerContent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(thread.enumerated()), id: \.element.phid) { idx, comment in
                if idx > 0 {
                    Divider()
                }
                CommentRow(
                    comment: comment,
                    user: comment.authorPHID.flatMap { userDirectory[$0] },
                    isOwn: comment.authorPHID == currentUserPHID,
                    onEdit: { onEditDraft(comment) },
                    onDelete: { onDeleteDraft(comment) }
                )
            }

            Divider()
            if let composerContent {
                composerContent()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            } else {
                HStack {
                    Spacer()
                    Button {
                        onReply()
                    } label: {
                        Label("Reply", systemImage: "arrowshape.turn.up.left")
                            .scaledFont(.caption)
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
    }
}

private struct CommentRow: View {
    let comment: InlineComment
    let user: PhabricatorUser?
    let isOwn: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isHovering: Bool = false

    private var isDraft: Bool { comment.transactionPHID == nil }

    private var authorName: String {
        user?.realName ?? user?.userName ?? "Unknown"
    }

    private var subtitle: String {
        var parts: [String] = []
        if let date = comment.dateCreated {
            parts.append(Self.relativeFormatter.localizedString(for: date, relativeTo: .now))
        }
        if isDraft {
            parts.append("Draft")
        }
        return parts.joined(separator: " · ")
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            UserAvatar(
                email: user?.primaryEmail,
                size: 22,
                imageURL: user?.image
            )
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(authorName)
                        .scaledFont(.callout)
                        .fontWeight(.semibold)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .scaledFont(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    actionButtons
                }
                RemarkupText(source: comment.content)
                    .scaledFont(.callout)
                    .textSelection(.enabled)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        #if os(macOS)
        .onHover { isHovering = $0 }
        #endif
    }

    @ViewBuilder
    private var actionButtons: some View {
        let shouldShow: Bool = {
            #if os(macOS)
            return isHovering
            #else
            return true
            #endif
        }()

        if shouldShow, isDraft, isOwn {
            HStack(spacing: 4) {
                Button {
                    onEdit()
                } label: {
                    Image(systemName: "pencil")
                        .scaledFont(.caption)
                }
                .buttonStyle(.plain)
                .help("Edit draft")
                Button {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                        .scaledFont(.caption)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .help("Delete draft")
            }
        }
    }
}
