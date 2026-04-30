import Foundation
import SwiftUI
import MarginaliaSyntax
import MarginaliaView

struct MarginaliaToolbar: View {
    let items: [Marginalia.ToolbarItem]
    @Binding var showPreview: Bool
    @Binding var text: String
    @Binding var selection: NSRange
    let canPreview: Bool

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items.indices, id: \.self) { i in
                view(for: items[i])
            }
        }
        .buttonStyle(.borderless)
    }

    @ViewBuilder
    private func view(for item: Marginalia.ToolbarItem) -> some View {
        switch item {
        case .divider:
            Divider().frame(height: 16)
        case .spacer:
            Spacer()
        case .action(let action):
            ToolbarButton(action: action, label: label(for: action), help: help(for: action), shortcut: shortcut(for: action)) {
                perform(action)
            }
            .disabled(action == .togglePreview && !canPreview)
        case .custom(_, let label, let symbol, let perform):
            Button(action: perform) {
                Image(systemName: symbol)
                    .frame(width: 24, height: 22)
            }
            .help(label)
        }
    }

    // MARK: - perform

    private func perform(_ action: Marginalia.Action) {
        switch action {
        case .bold:
            applyEdit(EditingOps.wrap(in: text, selection: selection, prefix: "**", suffix: "**", placeholder: "bold"))
        case .italic:
            applyEdit(EditingOps.wrap(in: text, selection: selection, prefix: "*", suffix: "*", placeholder: "italic"))
        case .strikethrough:
            applyEdit(EditingOps.wrap(in: text, selection: selection, prefix: "~~", suffix: "~~", placeholder: "strike"))
        case .heading(let level):
            applyEdit(EditingOps.prefixLines(in: text, selection: selection, marker: String(repeating: "#", count: level) + " "))
        case .unorderedList:
            applyEdit(EditingOps.prefixLines(in: text, selection: selection, marker: "- "))
        case .orderedList:
            applyEdit(EditingOps.numberedList(in: text, selection: selection))
        case .taskList:
            applyEdit(EditingOps.prefixLines(in: text, selection: selection, marker: "- [ ] "))
        case .blockquote:
            applyEdit(EditingOps.prefixLines(in: text, selection: selection, marker: "> "))
        case .codeSpan:
            applyEdit(EditingOps.wrap(in: text, selection: selection, prefix: "`", suffix: "`", placeholder: "code"))
        case .codeBlock:
            applyEdit(EditingOps.wrapCodeBlock(in: text, selection: selection))
        case .link:
            applyEdit(EditingOps.wrap(in: text, selection: selection, prefix: "[", suffix: "](url)", placeholder: "label"))
        case .horizontalRule:
            applyEdit(EditingOps.prefixLines(in: text, selection: selection, marker: "---\n"))
        case .togglePreview:
            showPreview.toggle()
        }
    }

    private func applyEdit(_ result: EditResult) {
        text = result.text
        selection = result.selection
    }

    // MARK: - labels

    private func label(for action: Marginalia.Action) -> String {
        switch action {
        case .bold: return "bold"
        case .italic: return "italic"
        case .strikethrough: return "strikethrough"
        case .heading(let level): return "h\(level)"
        case .unorderedList: return "list.bullet"
        case .orderedList: return "list.number"
        case .taskList: return "checklist"
        case .blockquote: return "text.quote"
        case .codeSpan: return "chevron.left.slash.chevron.right"
        case .codeBlock: return "curlybraces"
        case .link: return "link"
        case .horizontalRule: return "minus"
        case .togglePreview: return "eye"
        }
    }

    private func help(for action: Marginalia.Action) -> String {
        switch action {
        case .bold: return "Bold (⌘B)"
        case .italic: return "Italic (⌘I)"
        case .strikethrough: return "Strikethrough"
        case .heading(let level): return "Heading \(level)"
        case .unorderedList: return "Bullet list"
        case .orderedList: return "Numbered list"
        case .taskList: return "Task list"
        case .blockquote: return "Blockquote"
        case .codeSpan: return "Inline code"
        case .codeBlock: return "Code block"
        case .link: return "Link (⌘K)"
        case .horizontalRule: return "Horizontal rule"
        case .togglePreview: return "Toggle preview"
        }
    }

    private func shortcut(for action: Marginalia.Action) -> KeyboardShortcut? {
        switch action {
        case .bold: return KeyboardShortcut("b", modifiers: .command)
        case .italic: return KeyboardShortcut("i", modifiers: .command)
        case .link: return KeyboardShortcut("k", modifiers: .command)
        case .heading(let level) where (1...6).contains(level):
            return KeyboardShortcut(KeyEquivalent(Character(String(level))), modifiers: [.command, .option])
        default: return nil
        }
    }
}

private struct ToolbarButton: View {
    let action: Marginalia.Action
    let label: String
    let help: String
    let shortcut: KeyboardShortcut?
    let perform: () -> Void

    var body: some View {
        Group {
            if let shortcut {
                Button(action: perform) {
                    Image(systemName: label)
                        .frame(width: 24, height: 22)
                }
                .keyboardShortcut(shortcut)
            } else {
                Button(action: perform) {
                    Image(systemName: label)
                        .frame(width: 24, height: 22)
                }
            }
        }
        .help(help)
    }
}
