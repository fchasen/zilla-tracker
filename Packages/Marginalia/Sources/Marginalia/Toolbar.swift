import Foundation
import SwiftUI
import MarginaliaSyntax
import MarginaliaView

struct MarginaliaToolbar: View {
    let items: [Marginalia.ToolbarItem]
    @Binding var showPreview: Bool
    let canPreview: Bool
    let perform: (Marginalia.Action) -> Void

    var body: some View {
        let groups = makeGroups(from: items)
        HStack(spacing: 8) {
            ForEach(groups.indices, id: \.self) { i in
                groupView(groups[i])
            }
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
    }

    @ViewBuilder
    private func groupView(_ group: ToolbarGroup) -> some View {
        switch group {
        case .spacer:
            Spacer()
        case .items(let items):
            ControlGroup {
                ForEach(items.indices, id: \.self) { i in
                    button(for: items[i])
                }
            }
            .fixedSize()
        }
    }

    @ViewBuilder
    private func button(for item: Marginalia.ToolbarItem) -> some View {
        switch item {
        case .action(.heading(let level)):
            ToolbarLabelButton(
                label: "H\(level)",
                help: help(for: .heading(level: level)),
                shortcut: shortcut(for: .heading(level: level)),
                action: { perform(.heading(level: level)) }
            )
            .disabled(isDisabled(.heading(level: level)))
        case .action(let action):
            ToolbarActionButton(
                systemImage: label(for: action),
                help: help(for: action),
                shortcut: shortcut(for: action),
                action: { perform(action) }
            )
            .disabled(isDisabled(action))
        case let .custom(_, label, symbol, shortcut, _, customPerform):
            ToolbarActionButton(
                systemImage: symbol,
                help: label,
                shortcut: shortcut,
                action: customPerform
            )
            .disabled(showPreview)
        case .divider, .spacer:
            EmptyView()
        }
    }

    private func isDisabled(_ action: Marginalia.Action) -> Bool {
        if action == .togglePreview {
            return !canPreview
        }
        return showPreview
    }

    private func label(for action: Marginalia.Action) -> String {
        switch action {
        case .bold: return "bold"
        case .italic: return "italic"
        case .strikethrough: return "strikethrough"
        case .heading(let level): return "h\(level).square"
        case .unorderedList: return "list.bullet"
        case .orderedList: return "list.number"
        case .taskList: return "checklist"
        case .blockquote: return "text.quote"
        case .codeSpan: return "chevron.left.slash.chevron.right"
        case .codeBlock: return "curlybraces"
        case .link: return "link"
        case .horizontalRule: return "minus"
        case .togglePreview: return showPreview ? "pencil" : "eye"
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
        case .togglePreview: return showPreview ? "Edit" : "Preview"
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

/// Splits the toolbar list into runs separated by `.divider` (which becomes a
/// group break) and `.spacer` (which becomes a flexible spacer). Each run of
/// actions becomes one `ControlGroup` in the rendered toolbar so the buttons
/// read as related clusters rather than a single flat row.
private enum ToolbarGroup {
    case items([Marginalia.ToolbarItem])
    case spacer
}

private func makeGroups(from items: [Marginalia.ToolbarItem]) -> [ToolbarGroup] {
    var groups: [ToolbarGroup] = []
    var current: [Marginalia.ToolbarItem] = []

    func flush() {
        if !current.isEmpty {
            groups.append(.items(current))
            current.removeAll()
        }
    }

    for item in items {
        switch item {
        case .divider:
            flush()
        case .spacer:
            flush()
            groups.append(.spacer)
        default:
            current.append(item)
        }
    }
    flush()
    return groups
}

private struct ToolbarActionButton: View {
    let systemImage: String
    let help: String
    let shortcut: KeyboardShortcut?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 28, height: 24)
        }
        .help(help)
        .modifier(OptionalShortcut(shortcut: shortcut))
    }
}

private struct ToolbarLabelButton: View {
    let label: String
    let help: String
    let shortcut: KeyboardShortcut?
    let action: () -> Void

    @ScaledMetric(relativeTo: .body) private var labelSize: CGFloat = 13

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: labelSize, weight: .semibold))
                .frame(width: 28, height: 24)
        }
        .help(help)
        .modifier(OptionalShortcut(shortcut: shortcut))
    }
}

private struct OptionalShortcut: ViewModifier {
    let shortcut: KeyboardShortcut?

    func body(content: Content) -> some View {
        if let shortcut {
            content.keyboardShortcut(shortcut)
        } else {
            content
        }
    }
}

/// The toolbar's perform logic, extracted from the SwiftUI view so it's
/// directly unit-testable. Reads the *current* text and selection from the
/// `EditorController` (the source of truth — the SwiftUI selection binding
/// may be `.constant`, in which case the toolbar would otherwise wrap at
/// position 0 regardless of where the user's cursor is) and applies the
/// resulting `EditResult` back through `controller.applyEdit`, which clamps
/// out-of-bounds selections rather than crashing.
enum MarginaliaToolbarActions {
    static func perform(
        _ action: Marginalia.Action,
        controller: EditorController,
        text: Binding<String>,
        showPreview: Binding<Bool>
    ) {
        if action == .togglePreview {
            showPreview.wrappedValue.toggle()
            return
        }

        let currentText = controller.text
        let currentSelection = controller.clampedRange(controller.selection)

        let result: EditResult
        switch action {
        case .bold:
            result = EditingOps.wrap(in: currentText, selection: currentSelection, prefix: "**", suffix: "**", placeholder: "bold")
        case .italic:
            result = EditingOps.wrap(in: currentText, selection: currentSelection, prefix: "*", suffix: "*", placeholder: "italic")
        case .strikethrough:
            result = EditingOps.wrap(in: currentText, selection: currentSelection, prefix: "~~", suffix: "~~", placeholder: "strike")
        case .heading(let level):
            result = EditingOps.prefixLines(in: currentText, selection: currentSelection, marker: String(repeating: "#", count: level) + " ")
        case .unorderedList:
            result = EditingOps.applyListMarker(in: currentText, selection: currentSelection, kind: .bullet)
                ?? EditResult(text: currentText, selection: currentSelection)
        case .orderedList:
            result = EditingOps.applyListMarker(in: currentText, selection: currentSelection, kind: .numbered)
                ?? EditResult(text: currentText, selection: currentSelection)
        case .taskList:
            result = EditingOps.applyListMarker(in: currentText, selection: currentSelection, kind: .task)
                ?? EditResult(text: currentText, selection: currentSelection)
        case .blockquote:
            result = EditingOps.prefixLines(in: currentText, selection: currentSelection, marker: "> ")
        case .codeSpan:
            result = EditingOps.wrap(in: currentText, selection: currentSelection, prefix: "`", suffix: "`", placeholder: "code")
        case .codeBlock:
            result = EditingOps.wrapCodeBlock(in: currentText, selection: currentSelection)
        case .link:
            result = EditingOps.wrap(in: currentText, selection: currentSelection, prefix: "[", suffix: "](url)", placeholder: "label")
        case .horizontalRule:
            result = EditingOps.insertHorizontalRule(in: currentText, selection: currentSelection)
        case .togglePreview:
            return
        }

        controller.applyEdit(result)
        text.wrappedValue = result.text
    }
}
