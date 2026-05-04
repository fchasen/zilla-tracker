#if os(iOS)
import SwiftUI
import PhabricatorKit

struct RevisionCommentSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Workspace.self) private var workspace
    @Environment(PhabricatorAuthStore.self) private var phab

    @State private var isPosting: Bool = false

    private var draftBinding: Binding<String> {
        Binding(
            get: { workspace.loadedRevision.flatMap { workspace.revisionCommentDrafts[$0.id] } ?? "" },
            set: { newValue in
                guard let id = workspace.loadedRevision?.id else { return }
                if newValue.isEmpty {
                    workspace.revisionCommentDrafts.removeValue(forKey: id)
                } else {
                    workspace.revisionCommentDrafts[id] = newValue
                }
            }
        )
    }

    private var canPost: Bool {
        !draftBinding.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isPosting
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                MarkdownEditor(
                    text: draftBinding,
                    minHeight: 240,
                    isDisabled: isPosting,
                    bordered: false,
                    autoFocus: true
                )
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

    private func post() async {
        let trimmed = draftBinding.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let id = workspace.loadedRevision?.id else { return }
        isPosting = true
        defer { isPosting = false }
        if let error = await workspace.applyRevisionEdit(
            transactions: [.comment(Markdown.toRemarkup(trimmed))],
            using: phab.client
        ) {
            workspace.lastUpdateError = error.localizedDescription
            return
        }
        workspace.revisionCommentDrafts.removeValue(forKey: id)
        dismiss()
    }
}
#endif
