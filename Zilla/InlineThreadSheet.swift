#if os(iOS)
import SwiftUI
import PhabricatorKit

struct InlineThreadSheet: View {
    let rootPHID: String
    let thread: [InlineComment]
    let userDirectory: [String: PhabricatorUser]
    let currentUserPHID: String?
    let onEditDraft: (InlineComment) -> Void
    let onDeleteDraft: (InlineComment) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(Workspace.self) private var workspace
    @Environment(PhabricatorAuthStore.self) private var phab

    private var rootComment: InlineComment? { thread.first }

    private var composerForThisThread: ActiveInlineComposer? {
        guard let active = workspace.activeInlineComposer,
              let root = rootComment else { return nil }
        if active.replyTo == root.phid {
            return active
        }
        if let editing = active.editingPHID, thread.contains(where: { $0.phid == editing }) {
            return active
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    InlineThreadView(
                        thread: thread,
                        userDirectory: userDirectory,
                        currentUserPHID: currentUserPHID,
                        onReply: beginReply,
                        onEditDraft: onEditDraft,
                        onDeleteDraft: onDeleteDraft,
                        composerContent: composerForThisThread.map { active in
                            {
                                AnyView(
                                    InlineComposerHost(
                                        path: active.path,
                                        line: active.line,
                                        length: active.length,
                                        isNewFile: active.isNewFile,
                                        replyTo: active.replyTo,
                                        editingPHID: active.editingPHID,
                                        chromed: false
                                    )
                                )
                            }
                        }
                    )
                }
                .padding(12)
            }
            .navigationTitle("Comments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if composerForThisThread == nil {
                        Button("Reply") { beginReply() }
                    }
                }
            }
        }
    }

    private func beginReply() {
        guard let root = rootComment else { return }
        workspace.beginInlineComposer(
            path: root.path,
            line: root.line,
            length: max(1, root.length),
            isNewFile: root.isNewFile,
            replyTo: root.phid
        )
    }
}
#endif
