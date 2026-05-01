import SwiftUI
import FolioModel
import FolioHighlight

struct SplitFolioRow: View {
    let row: SplitRow
    let leftLineRange: NSRange?
    let rightLineRange: NSRange?
    let runs: [FolioHighlighter.Run]
    let theme: HighlightTheme
    let gutterWidth: CGFloat
    let leftMark: FolioCommentMark?
    let rightMark: FolioCommentMark?
    let onLeftMarkTap: (() -> Void)?
    let onRightMarkTap: (() -> Void)?
    let onCreateLeftComment: (() -> Void)?
    let onCreateRightComment: (() -> Void)?
    let isLeftInSelection: Bool
    let isRightInSelection: Bool
    let coordinateSpace: String

    @State private var isLeftHovered: Bool = false
    @State private var isRightHovered: Bool = false

    var body: some View {
        HStack(spacing: 0) {
            cell(side: .left)
            Rectangle()
                .fill(Color(theme.border))
                .frame(width: 1)
            cell(side: .right)
        }
        .font(.system(.caption, design: .monospaced))
        .lineLimit(nil)
        .fixedSize(horizontal: false, vertical: true)
    }

    private enum CellSide { case left, right }

    @ViewBuilder
    private func cell(side: CellSide) -> some View {
        let line = side == .left ? row.left : row.right
        let lineRange = side == .left ? leftLineRange : rightLineRange
        let number = side == .left ? line?.oldNumber : line?.newNumber
        let mark = side == .left ? leftMark : rightMark
        let onMarkTap = side == .left ? onLeftMarkTap : onRightMarkTap
        let onCreate = side == .left ? onCreateLeftComment : onCreateRightComment
        let inSelection = side == .left ? isLeftInSelection : isRightInSelection
        let isHovered = side == .left ? isLeftHovered : isRightHovered

        HStack(alignment: .top, spacing: 0) {
            gutter(text: number.map(String.init) ?? "")
            marker(for: line)
            CommentSlot(
                mark: mark,
                theme: theme,
                isHovered: isHovered,
                onMarkTap: onMarkTap,
                onCreate: onCreate
            )
            code(line: line, lineRange: lineRange)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(Color(gutterColor(for: line)))
                        .frame(width: gutterWidth + 8)
                    Rectangle()
                        .fill(Color(rowColor(for: line)))
                }
                if inSelection {
                    Rectangle().fill(Color(theme.selectionFill))
                }
            }
        }
        #if os(macOS)
        .onHover { hovering in
            if side == .left { isLeftHovered = hovering }
            else { isRightHovered = hovering }
        }
        #endif
        .reportingFolioCell(
            id: side == .left
                ? "split-l-\(row.left?.oldNumber ?? -1)"
                : "split-r-\(row.right?.newNumber ?? -1)",
            line: side == .left ? row.left?.oldNumber : row.right?.newNumber,
            side: side == .left ? .oldFile : .newFile,
            in: coordinateSpace
        )
    }

    private func gutter(text: String) -> some View {
        Text(text)
            .foregroundColor(Color(theme.lineNumber))
            .frame(width: gutterWidth, alignment: .trailing)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
    }

    private func marker(for line: DiffLine?) -> some View {
        Text(markerString(for: line))
            .foregroundColor(Color(theme.marker))
            .frame(width: 14, alignment: .center)
            .padding(.vertical, 1)
    }

    private func code(line: DiffLine?, lineRange: NSRange?) -> some View {
        Text(highlighted(line: line, lineRange: lineRange))
            .foregroundColor(Color(theme.foreground))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 4)
            .padding(.trailing, 8)
            .padding(.vertical, 1)
            .textSelection(.enabled)
    }

    private func highlighted(line: DiffLine?, lineRange: NSRange?) -> AttributedString {
        guard let line, let lineRange else { return AttributedString("") }
        return FolioHighlighter.attributed(
            text: line.text,
            lineRange: lineRange,
            runs: runs,
            defaultColor: theme.foreground
        )
    }

    private func markerString(for line: DiffLine?) -> String {
        guard let line else { return " " }
        switch line.kind {
        case .addition: return "+"
        case .deletion: return "-"
        case .context, .noNewline: return " "
        }
    }

    private func rowColor(for line: DiffLine?) -> PlatformColor {
        guard let line else { return theme.emptyMirror }
        switch line.kind {
        case .addition: return theme.addedRow
        case .deletion: return theme.removedRow
        case .context, .noNewline: return theme.contextRow
        }
    }

    private func gutterColor(for line: DiffLine?) -> PlatformColor {
        guard let line else { return theme.emptyMirror }
        switch line.kind {
        case .addition: return theme.addedGutter
        case .deletion: return theme.removedGutter
        case .context, .noNewline: return theme.contextGutter
        }
    }
}
