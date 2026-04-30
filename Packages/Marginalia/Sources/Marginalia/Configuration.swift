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

        public init(
            toolbar: [ToolbarItem] = Configuration.defaultToolbar,
            statusItems: [StatusItem] = [.words, .characters, .cursor]
        ) {
            self.toolbar = toolbar
            self.statusItems = statusItems
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
