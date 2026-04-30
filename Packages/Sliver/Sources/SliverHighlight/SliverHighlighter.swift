import Foundation
import SwiftTreeSitter

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
        guard language.id != CodeLanguage.plain.id,
              let tsLanguage = language.language,
              let queryURL = queryURL(for: language) else {
            return []
        }

        let parser = Parser()
        do {
            try parser.setLanguage(tsLanguage)
        } catch {
            return []
        }

        guard let tree = parser.parse(snippetText) else { return [] }
        guard let root = tree.rootNode else { return [] }

        let query: Query
        do {
            query = try Query(language: tsLanguage, url: queryURL)
        } catch {
            return []
        }

        let cursor = query.execute(node: root, in: tree)
        let highlights = cursor.highlights()

        return highlights.compactMap { named in
            guard let color = colorForCaptureName(named.nameComponents) else { return nil }
            let lo = Int(named.tsRange.bytes.lowerBound) / 2
            let hi = Int(named.tsRange.bytes.upperBound) / 2
            guard hi >= lo else { return nil }
            return Run(range: NSRange(location: lo, length: hi - lo), color: color)
        }
    }

    private func colorForCaptureName(_ components: [String]) -> PlatformColor? {
        let full = components.joined(separator: ".")
        if let color = CaptureMapping.color(for: full, theme: theme) { return color }
        guard let head = components.first else { return nil }
        return CaptureMapping.color(for: head, theme: theme)
    }

    private func queryURL(for language: CodeLanguage) -> URL? {
        guard let bundle = language.bundle, let resource = language.queryResource else { return nil }
        return bundle.url(forResource: resource, withExtension: "scm", subdirectory: "Queries")
            ?? bundle.url(forResource: resource, withExtension: "scm")
    }
}
