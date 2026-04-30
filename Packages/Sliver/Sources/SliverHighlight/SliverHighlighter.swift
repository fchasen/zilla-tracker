import Foundation

public final class SliverHighlighter {
    public struct Run: Sendable, Hashable {
        public let range: NSRange
        public let color: PlatformColor

        public init(range: NSRange, color: PlatformColor) {
            self.range = range
            self.color = color
        }
    }

    public let theme: HighlightTheme

    public init(theme: HighlightTheme) {
        self.theme = theme
    }

    public func runs(for snippetText: String, language: CodeLanguage) -> [Run] {
        guard language.id != CodeLanguage.plain.id else { return [] }
        return []
    }
}
