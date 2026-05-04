import SwiftUI
import PhabricatorKit

struct InlineComposerView: View {
    @Binding var text: String
    let isPosting: Bool
    let placeholder: String
    let postLabel: String
    let chromed: Bool
    let bordered: Bool
    let showToolbar: Bool
    let onCancel: () -> Void
    let onPost: () -> Void

    init(
        text: Binding<String>,
        isPosting: Bool = false,
        placeholder: String = "Write a comment…",
        postLabel: String = "Post",
        chromed: Bool = true,
        bordered: Bool = false,
        showToolbar: Bool = true,
        onCancel: @escaping () -> Void,
        onPost: @escaping () -> Void
    ) {
        self._text = text
        self.isPosting = isPosting
        self.placeholder = placeholder
        self.postLabel = postLabel
        self.chromed = chromed
        self.bordered = bordered
        self.showToolbar = showToolbar
        self.onCancel = onCancel
        self.onPost = onPost
    }

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canPost: Bool {
        !trimmed.isEmpty && !isPosting
    }

    var body: some View {
        let inner = VStack(alignment: .leading, spacing: 8) {
            MarkdownEditor(
                text: $text,
                minHeight: 36,
                isDisabled: isPosting,
                bordered: bordered,
                showToolbar: showToolbar
            )

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.escape, modifiers: [])
                    .disabled(isPosting)
                Button {
                    onPost()
                } label: {
                    if isPosting {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(postLabel)
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!canPost)
            }
        }

        if chromed {
            inner
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.background)
                )
        } else {
            inner
        }
    }
}
