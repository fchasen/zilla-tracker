import Foundation
import SwiftUI
import MarginaliaView
import MarginaliaRendering

// MARK: - environment values

private struct DialectKey: EnvironmentKey {
    static let defaultValue: Highlighter.Dialect = .commonMark
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue: MarginaliaTheme = .default
}

private struct ConfigurationKey: EnvironmentKey {
    static let defaultValue = Marginalia.Configuration()
}

private struct InlineContentProviderKey: EnvironmentKey {
    static let defaultValue: ((MarginaliaInlineContent) -> NSTextAttachment?)? = nil
}

public typealias MarginaliaPreviewRenderer = @Sendable (_ source: String, _ dialect: Highlighter.Dialect) -> AttributedString

private struct PreviewRendererKey: EnvironmentKey {
    static let defaultValue: MarginaliaPreviewRenderer? = nil
}

extension EnvironmentValues {
    public var marginaliaDialect: Highlighter.Dialect {
        get { self[DialectKey.self] }
        set { self[DialectKey.self] = newValue }
    }

    public var marginaliaTheme: MarginaliaTheme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }

    public var marginaliaConfiguration: Marginalia.Configuration {
        get { self[ConfigurationKey.self] }
        set { self[ConfigurationKey.self] = newValue }
    }

    public var marginaliaInlineContentProvider: ((MarginaliaInlineContent) -> NSTextAttachment?)? {
        get { self[InlineContentProviderKey.self] }
        set { self[InlineContentProviderKey.self] = newValue }
    }

    public var marginaliaPreviewRenderer: MarginaliaPreviewRenderer? {
        get { self[PreviewRendererKey.self] }
        set { self[PreviewRendererKey.self] = newValue }
    }
}

// MARK: - public modifiers

extension View {
    public func dialect(_ dialect: Highlighter.Dialect) -> some View {
        environment(\.marginaliaDialect, dialect)
    }

    public func theme(_ theme: MarginaliaTheme) -> some View {
        environment(\.marginaliaTheme, theme)
    }

    public func configuration(_ configuration: Marginalia.Configuration) -> some View {
        environment(\.marginaliaConfiguration, configuration)
    }

    public func inlineContentProvider(
        _ provider: @escaping (MarginaliaInlineContent) -> NSTextAttachment?
    ) -> some View {
        environment(\.marginaliaInlineContentProvider, provider)
    }

    public func previewRenderer(
        _ renderer: @escaping MarginaliaPreviewRenderer
    ) -> some View {
        environment(\.marginaliaPreviewRenderer, renderer)
    }

    public func defaultPreview(
        normalize: @escaping @Sendable (String, Highlighter.Dialect) -> String = { source, _ in source }
    ) -> some View {
        previewRenderer { source, dialect in
            let normalized = normalize(source, dialect)
            return (try? AttributedString(markdown: normalized)) ?? AttributedString(normalized)
        }
    }
}
