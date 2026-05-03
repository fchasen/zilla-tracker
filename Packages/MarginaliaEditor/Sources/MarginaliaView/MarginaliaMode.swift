import Foundation

/// How the editor renders the underlying markdown source.
public enum MarginaliaMode: String, Sendable, Equatable, CaseIterable {
    /// Markdown source is shown verbatim, with markup characters tinted via
    /// `theme.markupColor` and bullet/checkbox glyph substitutions still
    /// applied. The source storage and display storage are identical.
    case source

    /// Markdown syntax is elided in the display once the parser recognizes it
    /// — `# Heading` renders as `Heading`, `[label](url)` as `label`, etc.
    /// The source storage retains the markdown; the display storage holds the
    /// transformed string and a mapping translates positions both ways.
    case wysiwyg
}
