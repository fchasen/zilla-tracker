import SwiftUI
import FolioModel
import FolioHighlight
#if canImport(UIKit)
import UIKit
#endif

struct CodeFolioRow: View {
    let lineNumber: Int
    let text: String
    let lineRange: NSRange
    let runs: [FolioHighlighter.Run]
    let theme: HighlightTheme
    let gutterWidth: CGFloat
    let commentMark: FolioCommentMark?
    let onCommentMarkTap: (() -> Void)?
    let onCreateComment: (() -> Void)?
    let isInSelection: Bool
    let coordinateSpace: String

    @State private var isHovered: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Text(String(lineNumber))
                .foregroundColor(Color(theme.lineNumber))
                .frame(width: gutterWidth, alignment: .trailing)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
            CommentSlot(
                mark: commentMark,
                theme: theme,
                isHovered: isHovered,
                onMarkTap: onCommentMarkTap,
                onCreate: onCreateComment
            )
            Text(highlightedText)
                .foregroundColor(Color(theme.foreground))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 6)
                .padding(.trailing, 8)
                .padding(.vertical, 1)
                .textSelection(.enabled)
        }
        .background {
            ZStack {
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(Color(theme.contextGutter))
                        .frame(width: gutterWidth + 8)
                    Rectangle()
                        .fill(Color(theme.contextRow))
                }
                if isInSelection {
                    Rectangle().fill(Color(theme.selectionFill))
                }
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
            id: "code-\(lineNumber)",
            line: lineNumber,
            side: .newFile,
            in: coordinateSpace
        )
    }

    private var highlightedText: AttributedString {
        FolioHighlighter.attributed(
            text: text,
            lineRange: lineRange,
            runs: runs,
            defaultColor: theme.foreground
        )
    }
}
