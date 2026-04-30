import SwiftUI
import PhabricatorKit

struct RevisionCommentComposer: View {
    @Environment(Workspace.self) private var workspace
    @Environment(PhabricatorAuthStore.self) private var phab

    @State private var draftText: String = ""
    @State private var isPosting: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            InspectorSectionHeader(title: "Add comment")
            MarkdownEditor(
                text: $draftText,
                headerLabel: nil,
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
                .disabled(draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isPosting)
            }
        }
    }

    private func post() async {
        let trimmed = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isPosting = true
        defer { isPosting = false }
        if let error = await workspace.applyRevisionEdit(
            transactions: [.comment(trimmed)],
            using: phab.client
        ) {
            workspace.lastUpdateError = error.localizedDescription
            return
        }
        draftText = ""
    }
}
