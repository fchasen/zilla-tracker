import SwiftUI
import PhabricatorKit

struct RevisionCommentComposer: View {
    @Environment(Workspace.self) private var workspace
    @Environment(PhabricatorAuthStore.self) private var phab

    @State private var isPosting: Bool = false

    private var isBusy: Bool { isPosting || workspace.isUpdatingRevision }

    private var draftBinding: Binding<String> {
        Binding(
            get: { workspace.loadedRevision.flatMap { workspace.revisionCommentDrafts[$0.id] } ?? "" },
            set: { newValue in
                guard let id = workspace.loadedRevision?.id else { return }
                workspace.revisionCommentErrors.removeValue(forKey: id)
                if newValue.isEmpty {
                    workspace.revisionCommentDrafts.removeValue(forKey: id)
                } else {
                    workspace.revisionCommentDrafts[id] = newValue
                }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            InspectorSectionHeader(title: "Add comment")
            MarkdownEditor(
                text: draftBinding,
                isDisabled: isBusy,
                autolinksReferences: true,
                mentionCompletionContext: workspace.revisionMentionCompletionContext
            )
            .frame(minHeight: 100)

            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .scaledFont(.caption)
                    .foregroundStyle(.orange)
            }

            HStack {
                Spacer()
                Button {
                    Task { await post() }
                } label: {
                    if isPosting {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Post comment")
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(draftBinding.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isBusy)
            }
        }
    }

    private var error: String? {
        workspace.loadedRevision.flatMap { workspace.revisionCommentErrors[$0.id] }
    }

    private func post() async {
        guard let id = workspace.loadedRevision?.id else { return }
        let submitted = draftBinding.wrappedValue
        let trimmed = submitted.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            workspace.revisionCommentErrors[id] = "Enter a comment before posting."
            return
        }
        workspace.revisionCommentErrors.removeValue(forKey: id)
        isPosting = true
        defer { isPosting = false }
        if let error = await workspace.applyRevisionEdit(
            transactions: [.comment(Markdown.toRemarkup(CommentMarkdown.autolinkReferences(in: trimmed)))],
            using: phab.client
        ) {
            workspace.lastUpdateError = error.localizedDescription
            return
        }
        let current = workspace.revisionCommentDrafts[id] ?? ""
        if let remainder = DraftConsumption.remainder(after: submitted, in: current), !remainder.isEmpty {
            workspace.revisionCommentDrafts[id] = remainder
        } else {
            workspace.revisionCommentDrafts.removeValue(forKey: id)
        }
    }
}
