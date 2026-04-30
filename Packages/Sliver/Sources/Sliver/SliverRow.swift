import SwiftUI
import SliverModel
import SliverHighlight

struct SliverRow: View {
    let line: DiffLine
    let lineRange: NSRange
    let runs: [SliverHighlighter.Run]
    let theme: HighlightTheme
    let gutterWidth: CGFloat

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            gutter(text: line.oldNumber.map(String.init) ?? "")
                .background(Color(theme.gutterColor(for: line.kind)))
            gutter(text: line.newNumber.map(String.init) ?? "")
                .background(Color(theme.gutterColor(for: line.kind)))
            marker
            code
        }
        .background(Color(theme.rowColor(for: line.kind)))
        .font(.system(.caption, design: .monospaced))
        .lineLimit(nil)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func gutter(text: String) -> some View {
        Text(text)
            .foregroundColor(Color(theme.lineNumber))
            .frame(width: gutterWidth, alignment: .trailing)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
    }

    private var marker: some View {
        Text(line.kind.markerString)
            .foregroundColor(Color(theme.marker))
            .frame(width: 14, alignment: .center)
            .padding(.vertical, 1)
            .background(Color(theme.rowColor(for: line.kind)))
    }

    private var code: some View {
        Text(highlightedText)
            .foregroundColor(Color(theme.foreground))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 4)
            .padding(.trailing, 8)
            .padding(.vertical, 1)
            .textSelection(.enabled)
    }

    private var highlightedText: AttributedString {
        var attributed = AttributedString(line.text)
        guard !runs.isEmpty else { return attributed }
        let nsLine = line.text as NSString
        for run in runs {
            let intersection = NSIntersectionRange(run.range, lineRange)
            guard intersection.length > 0 else { continue }
            let local = NSRange(location: intersection.location - lineRange.location, length: intersection.length)
            guard local.location >= 0, local.location + local.length <= nsLine.length else { continue }
            if let lower = AttributedString.Index(
                String.Index(utf16Offset: local.location, in: line.text),
                within: attributed
            ),
            let upper = AttributedString.Index(
                String.Index(utf16Offset: local.location + local.length, in: line.text),
                within: attributed
            ) {
                attributed[lower..<upper].foregroundColor = run.color
            }
        }
        return attributed
    }
}

private extension DiffLine.Kind {
    var markerString: String {
        switch self {
        case .addition: return "+"
        case .deletion: return "-"
        case .context, .noNewline: return " "
        }
    }
}

extension HighlightTheme {
    func rowColor(for kind: DiffLine.Kind) -> PlatformColor {
        switch kind {
        case .addition: return addedRow
        case .deletion: return removedRow
        case .context, .noNewline: return contextRow
        }
    }

    func gutterColor(for kind: DiffLine.Kind) -> PlatformColor {
        switch kind {
        case .addition: return addedGutter
        case .deletion: return removedGutter
        case .context, .noNewline: return contextGutter
        }
    }
}
