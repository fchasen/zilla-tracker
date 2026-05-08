#if os(iOS)
import SwiftUI
import BugzillaKit

struct BugCommentSheet: View {
    @Environment(\.dismiss) private var dismiss

    let bugID: Bug.ID?
    @Binding var text: String
    let mentionCompletionContext: MentionCompletionContext
    let onPost: () -> Void
    let isPosting: Bool
    let error: String?

    private var canPost: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isPosting && bugID != nil
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                MarkdownEditor(
                    text: $text,
                    minHeight: 240,
                    isDisabled: isPosting,
                    bordered: false,
                    autolinksReferences: true,
                    mentionCompletionContext: mentionCompletionContext,
                    autoFocus: true
                )
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .scaledFont(.caption)
                        .foregroundStyle(.red)
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
                        onPost()
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
            .onChange(of: isPosting) { wasPosting, nowPosting in
                if wasPosting, !nowPosting, error == nil {
                    dismiss()
                }
            }
        }
    }
}
#endif
