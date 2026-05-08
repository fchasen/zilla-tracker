import SwiftUI
import FolioModel
import FolioHighlight
#if canImport(UIKit)
import UIKit
#endif

struct SplitFolioRow: View {
    let row: FolioRenderArtifact.SplitRowDescriptor
    let leftLine: DiffLine?
    let rightLine: DiffLine?
    let leftLineRange: NSRange?
    let rightLineRange: NSRange?
    let leftRuns: [FolioHighlighter.Run]
    let rightRuns: [FolioHighlighter.Run]
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
    let reportsSelection: Bool

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
        .scaledFont(.caption, design: .monospaced)
        .lineLimit(nil)
        .fixedSize(horizontal: false, vertical: true)
    }

    private enum CellSide { case left, right }

    @ViewBuilder
    private func cell(side: CellSide) -> some View {
        let line = side == .left ? leftLine : rightLine
        let lineRange = side == .left ? leftLineRange : rightLineRange
        let number = side == .left ? line?.oldNumber : line?.newNumber
        let mark = side == .left ? leftMark : rightMark
        let onMarkTap = side == .left ? onLeftMarkTap : onRightMarkTap
        let onCreate = side == .left ? onCreateLeftComment : onCreateRightComment
        let inSelection = side == .left ? isLeftInSelection : isRightInSelection
        let isHovered = side == .left ? isLeftHovered : isRightHovered
        let runs = side == .left ? leftRuns : rightRuns

        HStack(alignment: .top, spacing: 0) {
            gutter(text: number.map(String.init) ?? "", line: line)
            marker(for: line)
            CommentSlot(
                mark: mark,
                theme: theme,
                isHovered: isHovered,
                onMarkTap: onMarkTap,
                onCreate: onCreate
            )
            code(line: line, lineRange: lineRange, runs: runs, side: side)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                if line == nil {
                    DiagonalHatch(color: theme.emptyMirrorHatch, spacing: 6, lineWidth: 1)
                } else {
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(Color(gutterColor(for: line)))
                            .frame(width: gutterWidth + 8)
                        Rectangle()
                            .fill(Color(rowColor(for: line)))
                    }
                }
                if inSelection {
                    Rectangle().fill(Color(theme.selectionFill))
                }
            }
        }
        .overlay(alignment: .leading) {
            if let line, let accent = theme.accentColor(for: line.kind) {
                Rectangle()
                    .fill(Color(accent))
                    .frame(width: 3)
            }
        }
        #if os(macOS)
        .onHover { hovering in
            if side == .left { isLeftHovered = hovering }
            else { isRightHovered = hovering }
        }
        #else
        .onLongPressGesture(minimumDuration: 0.4, maximumDistance: 10) {
            guard let onCreate else { return }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onCreate()
        }
        #endif
        .reportingFolioCell(
            id: side == .left
                ? "split-l-\(leftLine?.oldNumber ?? -1)"
                : "split-r-\(rightLine?.newNumber ?? -1)",
            line: side == .left ? leftLine?.oldNumber : rightLine?.newNumber,
            side: side == .left ? .oldFile : .newFile,
            in: coordinateSpace,
            enabled: reportsSelection
        )
    }

    private func gutter(text: String, line: DiffLine?) -> some View {
        Text(text)
            .foregroundColor(Color(lineNumberColor(for: line)))
            .frame(width: gutterWidth, alignment: .trailing)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
    }

    private func lineNumberColor(for line: DiffLine?) -> PlatformColor {
        guard let line else { return theme.lineNumber }
        return theme.lineNumberColor(for: line.kind)
    }

    private func marker(for line: DiffLine?) -> some View {
        Text(markerString(for: line))
            .foregroundColor(Color(theme.marker))
            .frame(width: 14, alignment: .center)
            .padding(.vertical, 1)
    }

    private func code(
        line: DiffLine?,
        lineRange: NSRange?,
        runs: [FolioHighlighter.Run],
        side: CellSide
    ) -> some View {
        FolioHighlightedText(
            text: line?.text ?? "",
            lineRange: lineRange ?? NSRange(location: 0, length: 0),
            runs: runs,
            defaultColor: theme.foreground,
            backgroundRanges: intralineRanges(for: side),
            backgroundColor: intralineBackground(for: side),
            themeSignature: theme.paletteSignature
        )
            .equatable()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 4)
            .padding(.trailing, 8)
            .padding(.vertical, 1)
            .textSelection(.enabled)
    }

    private func intralineRanges(for side: CellSide) -> [NSRange] {
        guard let intra = row.intralineDiff else { return [] }
        return side == .left ? intra.oldRanges : intra.newRanges
    }

    private func intralineBackground(for side: CellSide) -> PlatformColor? {
        guard row.intralineDiff != nil else { return nil }
        return side == .left ? theme.intralineRemoved : theme.intralineAdded
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
