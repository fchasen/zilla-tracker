#if os(iOS)
import SwiftUI
import PhabricatorKit

struct RevisionCommentSheet: View {
    @Environment(\.dismiss) private var dismiss
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

    private var canPost: Bool {
        !draftBinding.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isBusy
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                MarkdownEditor(
                    text: draftBinding,
                    minHeight: 240,
                    isDisabled: isBusy,
                    bordered: false,
                    autoFocus: true,
                    autolinksReferences: true,
                    mentionCompletionContext: workspace.revisionMentionCompletionContext
                )
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .scaledFont(.caption)
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
                Spacer(minLength: 0)
            }
            .navigationTitle("New comment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await post() }
                    } label: {
                        if isPosting {
                            ProgressView()
                        } else {
                            Text("Post")
                        }
                    }
                    .disabled(!canPost)
                }
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
            workspace.revisionCommentErrors[id] = error.localizedDescription
            return
        }
        let current = workspace.revisionCommentDrafts[id] ?? ""
        if let remainder = DraftConsumption.remainder(after: submitted, in: current), !remainder.isEmpty {
            workspace.revisionCommentDrafts[id] = remainder
        } else {
            workspace.revisionCommentDrafts.removeValue(forKey: id)
        }
        dismiss()
    }
}
#endif
