import Foundation
import SwiftUI

extension MarkdownTextEditor {
    public typealias Action = EditorAction

    public enum ToolbarItem {
        case action(Action)
        case divider
        case spacer
        case custom(id: String, label: String, systemImage: String, shortcut: KeyboardShortcut? = nil, topLevel: Bool = false, action: () -> Void)
        case menu(id: String, label: String, systemImage: String, topLevel: Bool = false, entries: [MenuEntry])
    }

    public struct MenuEntry {
        public var id: String
        public var title: String
        public var systemImage: String?
        public var action: () -> Void

        public init(
            id: String,
            title: String,
            systemImage: String? = nil,
            action: @escaping () -> Void
        ) {
            self.id = id
            self.title = title
            self.systemImage = systemImage
            self.action = action
        }
    }

    public struct ContextMenuItem {
        public var title: String
        public var systemImage: String?
        public var isOn: Bool
        public var action: () -> Void

        public init(
            title: String,
            systemImage: String? = nil,
            isOn: Bool = false,
            action: @escaping () -> Void
        ) {
            self.title = title
            self.systemImage = systemImage
            self.isOn = isOn
            self.action = action
        }
    }

    public struct Configuration {
        public var toolbar: [ToolbarItem]
        public var contextMenuItems: [ContextMenuItem]
        public var sizing: EditorSizing
        public var minHeight: CGFloat
        public var spellChecking: MarkdownSpellChecking
        public var isEditable: Bool
        public var allowsCheckboxToggle: Bool
        public var onSubmit: (() -> Void)?

        public init(
            toolbar: [ToolbarItem] = Configuration.defaultToolbar,
            contextMenuItems: [ContextMenuItem] = [],
            sizing: EditorSizing = .fitsContent,
            minHeight: CGFloat = 96,
            spellChecking: MarkdownSpellChecking = .full,
            isEditable: Bool = true,
            allowsCheckboxToggle: Bool = false,
            onSubmit: (() -> Void)? = nil
        ) {
            self.toolbar = toolbar
            self.contextMenuItems = contextMenuItems
            self.sizing = sizing
            self.minHeight = minHeight
            self.spellChecking = spellChecking
            self.isEditable = isEditable
            self.allowsCheckboxToggle = allowsCheckboxToggle
            self.onSubmit = onSubmit
        }

        public static let defaultToolbar: [ToolbarItem] = [
            .action(.bold),
            .action(.italic),
            .action(.strikethrough),
            .divider,
            .action(.heading(level: 1)),
            .action(.heading(level: 2)),
            .action(.heading(level: 3)),
            .divider,
            .action(.unorderedList),
            .action(.orderedList),
            .action(.taskList),
            .action(.blockquote),
            .divider,
            .action(.codeSpan),
            .action(.codeBlock),
            .action(.link),
            .action(.horizontalRule)
        ]
    }
}

public extension Array where Element == MarkdownTextEditor.ToolbarItem {
    func replacing(_ action: MarkdownTextEditor.Action, with replacement: MarkdownTextEditor.ToolbarItem) -> [MarkdownTextEditor.ToolbarItem] {
        map { item in
            if case .action(let existing) = item, existing == action {
                return replacement
            }
            return item
        }
    }
}
