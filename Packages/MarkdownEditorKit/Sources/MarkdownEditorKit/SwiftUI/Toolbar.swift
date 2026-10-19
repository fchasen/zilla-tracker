import Foundation
import SwiftUI

struct EditorToolbar: View {
    let items: [MarkdownTextEditor.ToolbarItem]
    let perform: (MarkdownTextEditor.Action) -> Void
    var canPerform: (MarkdownTextEditor.Action) -> Bool = { _ in true }
    var isActive: (MarkdownTextEditor.Action) -> Bool = { _ in false }
    var isEnabled: Bool = true

    var body: some View {
        let groups = makeGroups(from: items)
        let row = HStack(spacing: 8) {
            ForEach(groups.indices, id: \.self) { i in
                groupView(groups[i])
            }
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .disabled(!isEnabled)
        #if os(iOS)
        ScrollView(.horizontal, showsIndicators: false) {
            row
                .padding(.vertical, 2)
        }
        .fixedSize(horizontal: false, vertical: true)
        #else
        row
        #endif
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
    private func button(for item: MarkdownTextEditor.ToolbarItem) -> some View {
        switch item {
        case .action(.heading(let level)):
            ToolbarLabelButton(
                label: "H\(level)",
                help: MarkdownTextEditor.Action.heading(level: level).helpText,
                shortcut: nil,
                isActive: isActive(.heading(level: level)),
                action: { perform(.heading(level: level)) }
            )
            .disabled(!canPerform(.heading(level: level)))
        case .action(let action):
            ToolbarActionButton(
                systemImage: action.systemImage,
                help: action.helpText,
                shortcut: nil,
                isActive: isActive(action),
                action: { perform(action) }
            )
            .disabled(!canPerform(action))
        case let .custom(_, label, symbol, shortcut, _, customPerform):
            ToolbarActionButton(
                systemImage: symbol,
                help: label,
                shortcut: shortcut,
                isActive: false,
                action: customPerform
            )
        case let .menu(_, label, symbol, _, entries):
            ToolbarMenuButton(systemImage: symbol, help: label, entries: entries)
        case .divider, .spacer:
            EmptyView()
        }
    }
}

private enum ToolbarGroup {
    case items([MarkdownTextEditor.ToolbarItem])
    case spacer
}

private func makeGroups(from items: [MarkdownTextEditor.ToolbarItem]) -> [ToolbarGroup] {
    var groups: [ToolbarGroup] = []
    var current: [MarkdownTextEditor.ToolbarItem] = []

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

private struct ToolbarMenuButton: View {
    let systemImage: String
    let help: String
    let entries: [MarkdownTextEditor.MenuEntry]

    var body: some View {
        Menu {
            ForEach(entries.indices, id: \.self) { i in
                let entry = entries[i]
                Button(action: entry.action) {
                    if let symbol = entry.systemImage {
                        Label(entry.title, systemImage: symbol)
                    } else {
                        Text(entry.title)
                    }
                }
            }
        } label: {
            Image(systemName: systemImage)
                .frame(width: ToolbarButtonMetrics.width, height: ToolbarButtonMetrics.height)
        }
        .menuIndicator(.hidden)
        .fixedSize()
        .help(help)
    }
}

private struct ToolbarActionButton: View {
    let systemImage: String
    let help: String
    let shortcut: KeyboardShortcut?
    var isActive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: ToolbarButtonMetrics.width, height: ToolbarButtonMetrics.height)
                .modifier(ActiveStateBackground(isActive: isActive))
        }
        .help(help)
        .modifier(OptionalShortcut(shortcut: shortcut))
    }
}

private struct ToolbarLabelButton: View {
    let label: String
    let help: String
    let shortcut: KeyboardShortcut?
    var isActive: Bool = false
    let action: () -> Void

    @ScaledMetric(relativeTo: .body) private var labelSize: CGFloat = 13

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: labelSize, weight: .semibold))
                .frame(width: ToolbarButtonMetrics.width, height: ToolbarButtonMetrics.height)
                .modifier(ActiveStateBackground(isActive: isActive))
        }
        .help(help)
        .modifier(OptionalShortcut(shortcut: shortcut))
    }
}

private struct ActiveStateBackground: ViewModifier {
    let isActive: Bool

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.accentColor.opacity(isActive ? 0.22 : 0))
            )
            .foregroundStyle(isActive ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
    }
}

private enum ToolbarButtonMetrics {
    #if os(iOS)
    static let width: CGFloat = 36
    static let height: CGFloat = 32
    #else
    static let width: CGFloat = 28
    static let height: CGFloat = 24
    #endif
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

extension EditorAction {
    var systemImage: String {
        switch self {
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
        case .indent: return "increase.indent"
        case .outdent: return "decrease.indent"
        }
    }

    var title: String {
        switch self {
        case .bold: return "Bold"
        case .italic: return "Italic"
        case .strikethrough: return "Strikethrough"
        case .heading(let level): return "Heading \(level)"
        case .unorderedList: return "Bullet List"
        case .orderedList: return "Numbered List"
        case .taskList: return "Task List"
        case .blockquote: return "Quote"
        case .codeSpan: return "Inline Code"
        case .codeBlock: return "Code Block"
        case .link: return "Link"
        case .horizontalRule: return "Horizontal Rule"
        case .indent: return "Indent"
        case .outdent: return "Outdent"
        }
    }

    var helpText: String {
        switch self {
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
        case .indent: return "Indent (⌘])"
        case .outdent: return "Outdent (⌘[)"
        }
    }
}

extension Array where Element == MarkdownTextEditor.ToolbarItem {
    var actions: [EditorAction] {
        compactMap { item in
            if case .action(let action) = item { return action }
            return nil
        }
    }
}

enum EditorToolbarActions {
    static func perform(
        _ action: MarkdownTextEditor.Action,
        controller: MarkdownEditorController
    ) {
        controller.perform(action)
    }
}
