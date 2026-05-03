import SwiftUI
import MarginaliaEditor
import PhabricatorKit

struct RevisionCommentComposer: View {
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            InspectorSectionHeader(title: "Add comment")
            MarkdownEditor(
                text: draftBinding,
                isDisabled: isPosting,
                dialect: .remarkup
            )
            .frame(minHeight: 100)

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
                .disabled(draftBinding.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isPosting)
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
    }
}
