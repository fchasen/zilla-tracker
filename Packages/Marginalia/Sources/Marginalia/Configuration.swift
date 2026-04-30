import Foundation
import SwiftUI
import MarginaliaView

extension Marginalia {

    /// What action a toolbar button or keyboard shortcut performs against the
    /// active selection.
    public enum Action: Sendable, Equatable {
        case bold
        case italic
        case heading(level: Int)
        case unorderedList
        case orderedList
        case taskList
        case blockquote
        case codeSpan
        case codeBlock
        case link
        case strikethrough
        case horizontalRule
        case togglePreview
    }

    /// One slot in the toolbar.
    public enum ToolbarItem {
        case action(Action)
        case divider
        case spacer
        case custom(id: String, label: LocalizedStringKey, systemImage: String, shortcut: KeyboardShortcut? = nil, action: () -> Void)
    }

    /// One slot in the status bar.
    public enum StatusItem: Sendable {
        case words
        case characters
        case cursor
        case dialect
    }

    /// Aggregate configuration. Defaults match the SimpleMDE-style toolbar.
    public struct Configuration {
        public var toolbar: [ToolbarItem]
        public var statusItems: [StatusItem]
        /// How the editor sizes itself within its SwiftUI parent. Defaults
        /// to `.fitsContent` — the editor's height tracks its content.
        /// Use `.fillContainer` for a fixed-height pane that scrolls
        /// internally.
        public var sizing: EditorSizing
        /// In `.fitsContent` mode, the editor starts at this height even
        /// when empty, then grows as content gets taller. Has no effect in
        /// `.fillContainer` mode.
        public var minHeight: CGFloat

        public init(
            toolbar: [ToolbarItem] = Configuration.defaultToolbar,
            statusItems: [StatusItem] = [.words, .characters, .cursor],
            sizing: EditorSizing = .fitsContent,
            minHeight: CGFloat = 96
        ) {
            self.toolbar = toolbar
            self.statusItems = statusItems
            self.sizing = sizing
            self.minHeight = minHeight
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
            .action(.horizontalRule),
            .spacer,
            .action(.togglePreview)
        ]
    }
}
