#if os(iOS)
import SwiftUI
import SwiftData
import PhabricatorKit
import MarginaliaEditor

struct InlineComposerSheet: View {
    let path: String
    let line: Int
    let length: Int
    let isNewFile: Bool
    let replyTo: String?
    let editingPHID: String?
    let titleText: String
    let previewContent: (() -> AnyView)?

    init(
        path: String,
        line: Int,
        length: Int,
        isNewFile: Bool,
        replyTo: String?,
        editingPHID: String? = nil,
        titleText: String,
        previewContent: (() -> AnyView)? = nil
    ) {
        self.path = path
        self.line = line
        self.length = length
        self.isNewFile = isNewFile
        self.replyTo = replyTo
        self.editingPHID = editingPHID
        self.titleText = titleText
        self.previewContent = previewContent
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(Workspace.self) private var workspace
    @Environment(PhabricatorAuthStore.self) private var phab

    @State private var text: String = ""
    @State private var isPosting: Bool = false
    @State private var loaded: Bool = false

    private var draftKey: InlineDraftKey? {
        guard let revision = workspace.loadedRevision,
              let diffID = workspace.loadedRevisionDiff?.id else {
            return nil
        }
        return InlineDraftKey(
            revisionID: revision.id,
            diffID: diffID,
            path: path,
            line: line,
            isNewFile: isNewFile,
            replyTo: replyTo
        )
    }

    private var canPost: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isPosting
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                if let previewContent {
                    previewContent()
                    Divider()
                }
                MarkdownEditor(
                    text: $text,
                    minHeight: 240,
                    isDisabled: isPosting,
                    dialect: .remarkup,
                    bordered: false,
                    autoFocus: true
                )
                Spacer(minLength: 0)
            }
            .navigationTitle(titleText)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        cancel()
                        dismiss()
                    }
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
        .onAppear { loadDraft() }
        .onChange(of: text) { _, newValue in
            guard loaded, let key = draftKey else { return }
            modelContext.saveInlineDraft(key, length: length, content: newValue)
        }
    }

    private func loadDraft() {
        guard let key = draftKey else { loaded = true; return }
        text = modelContext.loadInlineDraft(key)?.content ?? ""
        loaded = true
    }

    private func cancel() {
        if let key = draftKey {
            modelContext.clearInlineDraft(key)
        }
        text = ""
        workspace.cancelInlineComposer()
    }

    private func post() async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isPosting = true
        defer { isPosting = false }
        let error: Error?
        if let editingPHID {
            error = await workspace.editInlineDraft(
                phid: editingPHID,
                path: path,
                line: line,
                length: length,
                isNewFile: isNewFile,
                newContent: trimmed,
                replyTo: replyTo,
                using: phab.client
            )
        } else {
            error = await workspace.createInlineDraft(
                path: path,
                line: line,
                length: length,
                isNewFile: isNewFile,
                content: trimmed,
                replyTo: replyTo,
                using: phab.client
            )
        }
        if let error {
            workspace.lastUpdateError = error.localizedDescription
            return
        }
        if let key = draftKey {
            modelContext.clearInlineDraft(key)
        }
        text = ""
        workspace.cancelInlineComposer()
        dismiss()
    }
}
#endif
