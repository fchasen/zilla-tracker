import SwiftUI
import SliverModel
import SliverHighlight

public struct SliverView: View {
    public let path: String
    public let hunk: DiffHunk
    public let anchor: AnchorRange
    public let contextLines: Int
    public let isOutdated: Bool
    public let theme: HighlightTheme
    public let cornerRadius: CGFloat
    public let onPathTap: (() -> Void)?

    @State private var isExpanded: Bool = true

    public init(
        path: String,
        hunk: DiffHunk,
        anchor: AnchorRange,
        contextLines: Int = 3,
        isOutdated: Bool = false,
        theme: HighlightTheme = .light,
        cornerRadius: CGFloat = 6,
        onPathTap: (() -> Void)? = nil
    ) {
        self.path = path
        self.hunk = hunk
        self.anchor = anchor
        self.contextLines = contextLines
        self.isOutdated = isOutdated
        self.theme = theme
        self.cornerRadius = cornerRadius
        self.onPathTap = onPathTap
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if isExpanded {
                Divider().background(Color(theme.border))
                rows
            }
        }
        .background(Color(theme.contextRow.withAlpha(1)))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color(theme.border), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var header: some View {
        HStack(spacing: 6) {
            Button {
                isExpanded.toggle()
            } label: {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: 14, height: 14)
            }
            .buttonStyle(.plain)

            pathButton

            if isOutdated {
                outdatedBadge
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(theme.headerBackground))
    }

    @ViewBuilder
    private var pathButton: some View {
        if let onPathTap {
            Button(action: onPathTap) {
                Text(path)
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                    .foregroundStyle(.tint)
                    .underline(false)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            .buttonStyle(.plain)
            #if os(macOS)
            .modifier(LinkPointerStyle())
            #endif
        } else {
            Text(path)
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .lineLimit(1)
                .truncationMode(.head)
        }
    }

    private var outdatedBadge: some View {
        Text("Outdated")
            .font(.caption2.weight(.semibold))
            .foregroundColor(.orange)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .overlay(
                Capsule().strokeBorder(Color.orange, lineWidth: 1)
            )
    }

    private var rows: some View {
        let visible = SnippetWindow.slice(hunk: hunk, anchor: anchor, contextLines: contextLines)
        let snippetText = Array(visible).map(\.text).joined(separator: "\n")
        let highlighter = SliverHighlighter(theme: theme)
        let language = CodeLanguageRegistry.detect(path: path)
        let runs = highlighter.runs(for: snippetText, language: language)
        let lineRanges = computeLineRanges(visible: visible)
        let gutter = gutterWidth(for: visible)

        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(visible.enumerated()), id: \.offset) { index, line in
                SliverRow(
                    line: line,
                    lineRange: lineRanges[index],
                    runs: runs,
                    theme: theme,
                    gutterWidth: gutter
                )
            }
        }
    }

    private func computeLineRanges(visible: ArraySlice<DiffLine>) -> [NSRange] {
        var ranges: [NSRange] = []
        var cursor = 0
        for line in visible {
            let length = (line.text as NSString).length
            ranges.append(NSRange(location: cursor, length: length))
            cursor += length + 1
        }
        return ranges
    }

    private func gutterWidth(for visible: ArraySlice<DiffLine>) -> CGFloat {
        let widest = visible.reduce(0) { acc, line in
            let o = line.oldNumber.map { String($0).count } ?? 0
            let n = line.newNumber.map { String($0).count } ?? 0
            return max(acc, o, n)
        }
        return CGFloat(max(widest, 3)) * 7 + 4
    }
}

private extension PlatformColor {
    func withAlpha(_ a: CGFloat) -> PlatformColor {
        #if canImport(AppKit) && os(macOS)
        return self.withAlphaComponent(a)
        #else
        return self.withAlphaComponent(a)
        #endif
    }
}

#if os(macOS)
private struct LinkPointerStyle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.pointerStyle(.link)
        } else {
            content.onHover { hovering in
                if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
        }
    }
}
#endif
