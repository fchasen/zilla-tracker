import Foundation

/// Regex-based overlay tokenizer for Phabricator's Remarkup dialect.
///
/// Remarkup shares most of its surface with CommonMark (fences, code spans,
/// lists, blockquotes), so the editor reuses tree-sitter-markdown for the
/// shared subset. This overlay layers Remarkup-specific patterns on top:
///
/// - `//italic//` (Remarkup) — emitted as `.textEmphasis`
/// - `D123`, `T456` — Phabricator revision/task autolinks → `.textURI`
/// - `{F1234}`, `{P567}` — file/paste embeds → `.textURI`
/// - `@user` — user mentions → `.textReference`
/// - `NOTE:`, `WARNING:`, `IMPORTANT:`, `TODO:` — callout prefixes →
///   `.textTitle` (re-using the title style for visual emphasis)
/// - `=…=` and `==…==` — Remarkup heading levels → `.textTitle`
public enum RemarkupGrammar {
    public static func highlights(in text: String) -> [HighlightSpan] {
        var spans: [HighlightSpan] = []
        spans.append(contentsOf: matches(text, pattern: #"//[^/\n]+//"#, tag: .textEmphasis))
        spans.append(contentsOf: matches(text, pattern: #"\b[DT]\d+\b"#, tag: .textURI))
        spans.append(contentsOf: matches(text, pattern: #"\{[FP]\d+(?:[^}]*)\}"#, tag: .textURI))
        spans.append(contentsOf: matches(text, pattern: #"@[A-Za-z0-9_.-]+"#, tag: .textReference))
        spans.append(contentsOf: matches(text, pattern: #"(?m)^(NOTE|WARNING|IMPORTANT|TODO):"#, tag: .textTitle))
        spans.append(contentsOf: matches(text, pattern: #"(?m)^={2,}\s.+\s={2,}$"#, tag: .textTitle))
        spans.sort { $0.range.location < $1.range.location }
        return spans
    }

    private static func matches(_ text: String, pattern: String, tag: HighlightTag) -> [HighlightSpan] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)
        return regex.matches(in: text, range: range).map {
            HighlightSpan(range: $0.range, tag: tag)
        }
    }
}
