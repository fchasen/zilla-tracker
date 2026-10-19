import Foundation
import SwiftUI

private struct ThemeKey: EnvironmentKey {
    static let defaultValue: MarkdownEditorTheme = .default
}

private struct ConfigurationKey: EnvironmentKey {
    static let defaultValue = MarkdownTextEditor.Configuration()
}

private struct InlineContentProviderKey: EnvironmentKey {
    static let defaultValue: InlineContentProvider? = nil
}

private struct InlineContentRulesKey: EnvironmentKey {
    static let defaultValue: [InlineContentRule] = []
}

private struct EditorReadyKey: EnvironmentKey {
    static let defaultValue: ((MarkdownEditorController) -> Void)? = nil
}

extension EnvironmentValues {
    public var markdownEditorTheme: MarkdownEditorTheme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }

    public var markdownEditorConfiguration: MarkdownTextEditor.Configuration {
        get { self[ConfigurationKey.self] }
        set { self[ConfigurationKey.self] = newValue }
    }

    public var markdownInlineContentProvider: InlineContentProvider? {
        get { self[InlineContentProviderKey.self] }
        set { self[InlineContentProviderKey.self] = newValue }
    }

    public var markdownInlineContentRules: [InlineContentRule] {
        get { self[InlineContentRulesKey.self] }
        set { self[InlineContentRulesKey.self] = newValue }
    }

    public var markdownEditorReady: ((MarkdownEditorController) -> Void)? {
        get { self[EditorReadyKey.self] }
        set { self[EditorReadyKey.self] = newValue }
    }
}

extension View {
    public func markdownEditorTheme(_ theme: MarkdownEditorTheme) -> some View {
        environment(\.markdownEditorTheme, theme)
    }

    public func markdownEditorConfiguration(_ configuration: MarkdownTextEditor.Configuration) -> some View {
        environment(\.markdownEditorConfiguration, configuration)
    }

    public func inlineContentProvider(
        _ provider: @escaping InlineContentProvider
    ) -> some View {
        environment(\.markdownInlineContentProvider, provider)
    }

    public func inlineContentRules(_ rules: [InlineContentRule]) -> some View {
        environment(\.markdownInlineContentRules, rules)
    }

    public func onMarkdownEditorReady(
        _ callback: @escaping (MarkdownEditorController) -> Void
    ) -> some View {
        environment(\.markdownEditorReady, callback)
    }

    public func markdownEditorEditable(_ isEditable: Bool = true) -> some View {
        transformEnvironment(\.markdownEditorConfiguration) { config in
            config.isEditable = isEditable
        }
    }
}
