import SwiftUI
import SwiftData
import PhabricatorKit

struct InlineComposerHost: View {
    let path: String
    let line: Int
    let length: Int
    let isNewFile: Bool
    let replyTo: String?
    let editingPHID: String?
    let initialContent: String?
    let chromed: Bool
    let showToolbar: Bool

    init(
        path: String,
        line: Int,
        length: Int,
        isNewFile: Bool,
        replyTo: String?,
        editingPHID: String? = nil,
        initialContent: String? = nil,
        chromed: Bool = true,
        showToolbar: Bool = true
    ) {
        self.path = path
        self.line = line
        self.length = length
        self.isNewFile = isNewFile
        self.replyTo = replyTo
        self.editingPHID = editingPHID
        self.initialContent = initialContent
        self.chromed = chromed
        self.showToolbar = showToolbar
    }

    @Environment(\.modelContext) private var modelContext
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

    var body: some View {
        InlineComposerView(
            text: $text,
            isPosting: isPosting,
            placeholder: editingPHID != nil ? "Edit draft…" : (replyTo == nil ? "Add a comment…" : "Reply…"),
            postLabel: editingPHID != nil ? "Save" : "Post",
            chromed: chromed,
            showToolbar: showToolbar,
            mentionCompletionContext: workspace.revisionMentionCompletionContext,
            onCancel: cancel,
            onPost: { Task { await post() } }
        )
        .onAppear { loadDraft() }
        .onChange(of: text) { _, newValue in
            guard loaded, let key = draftKey else { return }
            modelContext.saveInlineDraft(key, length: length, content: newValue)
        }
    }

    private func loadDraft() {
        guard let key = draftKey else { loaded = true; return }
        if let buffer = modelContext.loadInlineDraft(key) {
            text = buffer.content
        } else if let initialContent {
            text = Remarkup.toCommonMark(initialContent)
        } else {
            text = ""
        }
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
        let submitted = text
        let key = draftKey
        let trimmed = submitted.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let body = Markdown.toRemarkup(CommentMarkdown.autolinkReferences(in: trimmed))
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
                newContent: body,
                replyTo: replyTo,
                using: phab.client
            )
        } else {
            error = await workspace.createInlineDraft(
                path: path,
                line: line,
                length: length,
                isNewFile: isNewFile,
                content: body,
                replyTo: replyTo,
                using: phab.client
            )
        }
        if let error {
            workspace.lastUpdateError = error.localizedDescription
            return
        }
        if let key {
            let current = modelContext.loadInlineDraft(key)?.content ?? text
            let remainder = DraftConsumption.remainder(after: submitted, in: current)
            if let remainder {
                modelContext.saveInlineDraft(key, length: length, content: remainder)
            } else {
                modelContext.clearInlineDraft(key)
            }
            text = remainder ?? ""
        }
        // A successful post rotates the inline's PHID — create mints one the
        // composer never sees, edit deletes and recreates — so the composer
        // closes rather than let a second Post duplicate the draft.
        workspace.cancelInlineComposer()
    }
}
