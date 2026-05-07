import SwiftUI
import FolioModel
import FolioHighlight
#if canImport(UIKit)
import UIKit
#endif

struct FolioRow: View {
    let line: DiffLine
    let lineRange: NSRange
    let runs: [FolioHighlighter.Run]
    let theme: HighlightTheme
    let gutterWidth: CGFloat
    let commentMark: FolioCommentMark?
    let onCommentMarkTap: (() -> Void)?
    let onCreateComment: (() -> Void)?
    let isInSelection: Bool
    let coordinateSpace: String
    let reportsSelection: Bool
    let intralineRanges: [NSRange]

    @State private var isHovered: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            gutter(text: line.oldNumber.map(String.init) ?? "")
            gutter(text: line.newNumber.map(String.init) ?? "")
            marker
            CommentSlot(
                mark: commentMark,
                theme: theme,
                isHovered: isHovered,
                onMarkTap: onCommentMarkTap,
                onCreate: onCreateComment
            )
            code
        }
        .background {
            ZStack {
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(Color(theme.gutterColor(for: line.kind)))
                        .frame(width: gutterWidth + 8)
                    Rectangle()
                        .fill(Color(theme.gutterColor(for: line.kind)))
                        .frame(width: gutterWidth + 8)
                    Rectangle()
                        .fill(Color(theme.rowColor(for: line.kind)))
                }
                if isInSelection {
                    Rectangle().fill(Color(theme.selectionFill))
                }
            }
        }
        .overlay(alignment: .leading) {
            if let accent = theme.accentColor(for: line.kind) {
                Rectangle()
                    .fill(Color(accent))
                    .frame(width: 3)
            }
        }
        .scaledFont(.caption, design: .monospaced)
        .lineLimit(nil)
        .fixedSize(horizontal: false, vertical: true)
        #if os(macOS)
        .onHover { isHovered = $0 }
        #else
        .onLongPressGesture(minimumDuration: 0.4, maximumDistance: 10) {
            guard let onCreateComment else { return }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onCreateComment()
        }
        #endif
        .reportingFolioCell(
            id: "u-\(line.kind)-\(line.oldNumber ?? -1)-\(line.newNumber ?? -1)",
            line: selectionLine,
            side: selectionSide,
            in: coordinateSpace,
            enabled: reportsSelection
        )
    }

    private var selectionLine: Int? {
        switch line.kind {
        case .addition: return line.newNumber
        case .deletion: return line.oldNumber
        case .context: return line.newNumber ?? line.oldNumber
        case .noNewline: return nil
        }
    }

    private var selectionSide: AnchorRange.Side {
        line.kind == .deletion ? .oldFile : .newFile
    }

    private func gutter(text: String) -> some View {
        Text(text)
            .foregroundColor(Color(theme.lineNumberColor(for: line.kind)))
            .frame(width: gutterWidth, alignment: .trailing)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
    }

    private var marker: some View {
        Text(line.kind.markerString)
            .foregroundColor(Color(theme.marker))
            .frame(width: 14, alignment: .center)
            .padding(.vertical, 1)
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
        var attr = FolioHighlighter.attributed(
            text: line.text,
            lineRange: lineRange,
            runs: runs,
            defaultColor: theme.foreground
        )
        if !intralineRanges.isEmpty, let bg = intralineBackground {
            for range in intralineRanges {
                attr.applyBackground(on: line.text, range: range, color: bg)
            }
        }
        return attr
    }

    private var intralineBackground: PlatformColor? {
        switch line.kind {
        case .addition: return theme.intralineAdded
        case .deletion: return theme.intralineRemoved
        case .context, .noNewline: return nil
        }
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

    func lineNumberColor(for kind: DiffLine.Kind) -> PlatformColor {
        switch kind {
        case .addition: return addedLineNumber
        case .deletion: return removedLineNumber
        case .context, .noNewline: return lineNumber
        }
    }

    func accentColor(for kind: DiffLine.Kind) -> PlatformColor? {
        switch kind {
        case .addition: return addedAccent
        case .deletion: return removedAccent
        case .context, .noNewline: return nil
        }
    }
}
