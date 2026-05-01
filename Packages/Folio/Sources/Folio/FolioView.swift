import SwiftUI
import FolioModel
import FolioHighlight

public struct FolioView: View {
    public let path: String
    public let content: FolioContent
    public let initialContextLines: Int
    public let isOutdated: Bool
    public let showsHeader: Bool
    public let theme: HighlightTheme
    public let cornerRadius: CGFloat
    public let commentMarks: [FolioCommentMark]
    public let onPathTap: (() -> Void)?
    public let onCommentMarkTap: ((FolioCommentMark) -> Void)?
    public let onCreateComment: ((Int, AnchorRange.Side) -> Void)?
    public let onExpandContext: ((ExpandDirection) -> Void)?
    public let onLineSelectionChange: ((FolioLineSelection?) -> Void)?
    public let selection: Binding<FolioLineSelection?>?

    @State private var isExpanded: Bool = true
    @State private var contextAbove: Int
    @State private var contextBelow: Int
    @State private var selectionCells: [FolioSelectableCell] = []
    @State private var draftSelection: FolioLineSelection?
    @State private var gapStates: [Int: GapRevealState] = [:]

    private let expandStep: Int = 10
    private let gapExpandStep: Int = 20

    struct GapRevealState: Equatable {
        var revealedFromTop: Int = 0
        var revealedFromBottom: Int = 0
    }

    public init(
        path: String,
        content: FolioContent,
        contextLines: Int = 3,
        isOutdated: Bool = false,
        showsHeader: Bool = true,
        theme: HighlightTheme = .light,
        cornerRadius: CGFloat = 6,
        commentMarks: [FolioCommentMark] = [],
        selection: Binding<FolioLineSelection?>? = nil,
        onPathTap: (() -> Void)? = nil,
        onCommentMarkTap: ((FolioCommentMark) -> Void)? = nil,
        onCreateComment: ((Int, AnchorRange.Side) -> Void)? = nil,
        onExpandContext: ((ExpandDirection) -> Void)? = nil,
        onLineSelectionChange: ((FolioLineSelection?) -> Void)? = nil
    ) {
        self.path = path
        self.content = content
        self.initialContextLines = contextLines
        self.isOutdated = isOutdated
        self.showsHeader = showsHeader
        self.theme = theme
        self.cornerRadius = cornerRadius
        self.commentMarks = commentMarks
        self.selection = selection
        self.onPathTap = onPathTap
        self.onCommentMarkTap = onCommentMarkTap
        self.onCreateComment = onCreateComment
        self.onExpandContext = onExpandContext
        self.onLineSelectionChange = onLineSelectionChange
        self._contextAbove = State(initialValue: contextLines)
        self._contextBelow = State(initialValue: contextLines)
        self._isExpanded = State(initialValue: !showsHeader || true)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsHeader {
                header
                if isExpanded {
                    Divider().background(Color(theme.border))
                }
            }
            if isExpanded || !showsHeader {
                rows
                    .coordinateSpace(name: FolioSelectionMath.coordinateSpaceName)
                    .gesture(selectionDragGesture)
                    .onPreferenceChange(FolioSelectableCellsPreference.self) { cells in
                        selectionCells = cells
                    }
            }
        }
        .background(Color(theme.contextRow.withAlpha(1)))
        .overlay {
            if cornerRadius > 0 {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color(theme.border), lineWidth: 1)
            } else {
                Rectangle()
                    .strokeBorder(Color(theme.border), lineWidth: 1)
            }
        }
        .clipShape(cornerRadius > 0
            ? AnyShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            : AnyShape(Rectangle()))
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

            if showOutdatedBadge {
                outdatedBadge
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(theme.headerBackground))
    }

    private var showOutdatedBadge: Bool {
        guard isOutdated else { return false }
        if case .code = content { return false }
        return true
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

    @ViewBuilder
    private var rows: some View {
        switch content {
        case let .diff(hunk, anchor, mode):
            diffBody(hunk: hunk, anchor: anchor, mode: mode)
        case let .code(text, startLine):
            codeBody(text: text, startLine: startLine)
        }
    }

    @ViewBuilder
    private func diffBody(hunk: DiffHunk, anchor: AnchorRange?, mode: DiffViewMode) -> some View {
        if let anchor {
            anchoredDiffBody(hunk: hunk, anchor: anchor, mode: mode)
        } else {
            foldedDiffBody(hunk: hunk, mode: mode)
        }
    }

    @ViewBuilder
    private func anchoredDiffBody(hunk: DiffHunk, anchor: AnchorRange, mode: DiffViewMode) -> some View {
        let bounds = SnippetWindow.bounds(
            hunk: hunk,
            anchor: anchor,
            contextAbove: contextAbove,
            contextBelow: contextBelow
        )
        let resources = highlightResources(for: hunk)
        let gutter = gutterWidth(for: hunk.lines[...])
        let leadingGutter = gutter + 8
        let trailingGutter: CGFloat? = mode == .split ? leadingGutter : nil

        VStack(alignment: .leading, spacing: 0) {
            if bounds.linesAbove > 0 || onExpandContext != nil {
                ExpandContextRow(
                    label: ExpandContextRow.unmodifiedLabel(count: bounds.linesAbove),
                    theme: theme,
                    leadingGutterWidth: leadingGutter,
                    trailingGutterWidth: trailingGutter,
                    onExpandFromBottom: {
                        withAnimation(.snappy(duration: 0.18)) {
                            expand(direction: .up, bounds: bounds)
                        }
                    }
                )
            }
            renderRowRange(
                hunk: hunk,
                range: bounds.startIndex...max(bounds.startIndex, bounds.endIndex),
                lineRanges: resources.lineRanges,
                runs: resources.runs,
                gutter: gutter,
                mode: mode
            )
            if bounds.linesBelow > 0 || onExpandContext != nil {
                ExpandContextRow(
                    label: ExpandContextRow.unmodifiedLabel(count: bounds.linesBelow),
                    theme: theme,
                    leadingGutterWidth: leadingGutter,
                    trailingGutterWidth: trailingGutter,
                    onExpandFromTop: {
                        withAnimation(.snappy(duration: 0.18)) {
                            expand(direction: .down, bounds: bounds)
                        }
                    }
                )
            }
        }
    }

    private enum GapPosition { case leading, trailing, middle, standalone }

    private func position(of idx: Int, in sections: [FoldedDiff.Section]) -> GapPosition {
        let beforeHasLines = sections.prefix(idx).contains { if case .lines = $0 { true } else { false } }
        let afterHasLines = sections.dropFirst(idx + 1).contains { if case .lines = $0 { true } else { false } }
        switch (beforeHasLines, afterHasLines) {
        case (false, true): return .leading
        case (true, false): return .trailing
        case (true, true): return .middle
        case (false, false): return .standalone
        }
    }

    @ViewBuilder
    private func foldedDiffBody(hunk: DiffHunk, mode: DiffViewMode) -> some View {
        let folded = DiffFolder.fold(hunk, contextLines: initialContextLines)
        let resources = highlightResources(for: hunk)
        let gutter = gutterWidth(for: hunk.lines[...])
        let leadingGutter = gutter + 8
        let trailingGutter: CGFloat? = mode == .split ? leadingGutter : nil

        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(folded.sections.enumerated()), id: \.offset) { idx, section in
                switch section {
                case let .lines(start, end):
                    renderRowRange(
                        hunk: hunk,
                        range: start...end,
                        lineRanges: resources.lineRanges,
                        runs: resources.runs,
                        gutter: gutter,
                        mode: mode
                    )
                case let .gap(start, end):
                    foldedGap(
                        idx: idx,
                        start: start,
                        end: end,
                        sections: folded.sections,
                        hunk: hunk,
                        resources: resources,
                        gutter: gutter,
                        leadingGutter: leadingGutter,
                        trailingGutter: trailingGutter,
                        mode: mode
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func foldedGap(
        idx: Int,
        start: Int,
        end: Int,
        sections: [FoldedDiff.Section],
        hunk: DiffHunk,
        resources: HighlightResources,
        gutter: CGFloat,
        leadingGutter: CGFloat,
        trailingGutter: CGFloat?,
        mode: DiffViewMode
    ) -> some View {
        let state = gapStates[start] ?? GapRevealState()
        let totalSize = end - start + 1
        let revealed = state.revealedFromTop + state.revealedFromBottom
        let hiddenStart = start + state.revealedFromTop
        let hiddenEnd = end - state.revealedFromBottom
        let hiddenCount = max(0, hiddenEnd - hiddenStart + 1)
        let pos = position(of: idx, in: sections)

        return Group {
            if revealed >= totalSize {
                renderRowRange(
                    hunk: hunk,
                    range: start...end,
                    lineRanges: resources.lineRanges,
                    runs: resources.runs,
                    gutter: gutter,
                    mode: mode
                )
            } else {
                if state.revealedFromTop > 0 {
                    renderRowRange(
                        hunk: hunk,
                        range: start...(start + state.revealedFromTop - 1),
                        lineRanges: resources.lineRanges,
                        runs: resources.runs,
                        gutter: gutter,
                        mode: mode
                    )
                }
                ExpandContextRow(
                    label: ExpandContextRow.unmodifiedLabel(count: hiddenCount),
                    theme: theme,
                    leadingGutterWidth: leadingGutter,
                    trailingGutterWidth: trailingGutter,
                    onExpandFromTop: (pos == .leading) ? nil : {
                        withAnimation(.snappy(duration: 0.18)) {
                            expandGap(start: start, totalSize: totalSize, fromTop: true)
                        }
                    },
                    onExpandFromBottom: (pos == .trailing) ? nil : {
                        withAnimation(.snappy(duration: 0.18)) {
                            expandGap(start: start, totalSize: totalSize, fromTop: false)
                        }
                    }
                )
                if state.revealedFromBottom > 0 {
                    renderRowRange(
                        hunk: hunk,
                        range: (end - state.revealedFromBottom + 1)...end,
                        lineRanges: resources.lineRanges,
                        runs: resources.runs,
                        gutter: gutter,
                        mode: mode
                    )
                }
            }
        }
    }

    private func expandGap(start: Int, totalSize: Int, fromTop: Bool) {
        var state = gapStates[start] ?? GapRevealState()
        let remaining = totalSize - state.revealedFromTop - state.revealedFromBottom
        let bump = min(gapExpandStep, remaining)
        if fromTop {
            state.revealedFromTop += bump
        } else {
            state.revealedFromBottom += bump
        }
        gapStates[start] = state
    }

    private struct HighlightResources {
        let runs: [FolioHighlighter.Run]
        let lineRanges: [NSRange]
    }

    private func highlightResources(for hunk: DiffHunk) -> HighlightResources {
        let allText = hunk.lines.map(\.text).joined(separator: "\n")
        let highlighter = FolioHighlighter(theme: theme)
        let language = CodeLanguageRegistry.detect(path: path)
        let runs = highlighter.runs(for: allText, language: language)
        var lineRanges: [NSRange] = []
        var cursor = 0
        for line in hunk.lines {
            let length = (line.text as NSString).length
            lineRanges.append(NSRange(location: cursor, length: length))
            cursor += length + 1
        }
        return HighlightResources(runs: runs, lineRanges: lineRanges)
    }

    @ViewBuilder
    private func renderRowRange(
        hunk: DiffHunk,
        range: ClosedRange<Int>,
        lineRanges: [NSRange],
        runs: [FolioHighlighter.Run],
        gutter: CGFloat,
        mode: DiffViewMode
    ) -> some View {
        let visible = Array(hunk.lines[range])
        switch mode {
        case .unified:
            let intralineByIdx = unifiedIntralineRanges(visible)
            ForEach(Array(visible.enumerated()), id: \.offset) { i, line in
                let absIdx = range.lowerBound + i
                let lookup = unifiedLookup(for: line)
                FolioRow(
                    line: line,
                    lineRange: lineRanges[absIdx],
                    runs: runs,
                    theme: theme,
                    gutterWidth: gutter,
                    commentMark: lookup.mark,
                    onCommentMarkTap: lookup.mark.flatMap { m in onCommentMarkTap.map { handler in { handler(m) } } },
                    onCreateComment: createCommentClosure(line: lookup.lineNum, side: lookup.side),
                    isInSelection: isLineSelected(lookup.lineNum, side: lookup.side),
                    coordinateSpace: FolioSelectionMath.coordinateSpaceName,
                    intralineRanges: intralineByIdx[i] ?? []
                )
            }
        case .split:
            let splitRows = SplitRowBuilder.build(visible)
            let pairs = splitRowRangesAbsolute(
                rows: splitRows,
                lineRanges: lineRanges,
                visible: visible,
                baseIndex: range.lowerBound
            )
            ForEach(Array(splitRows.enumerated()), id: \.offset) { idx, row in
                let leftLine = row.left?.oldNumber
                let rightLine = row.right?.newNumber
                let leftMark = leftLine.flatMap { findMark(side: .oldFile, line: $0) }
                let rightMark = rightLine.flatMap { findMark(side: .newFile, line: $0) }
                SplitFolioRow(
                    row: row,
                    leftLineRange: pairs[idx].leftRange,
                    rightLineRange: pairs[idx].rightRange,
                    runs: runs,
                    theme: theme,
                    gutterWidth: gutter,
                    leftMark: leftMark,
                    rightMark: rightMark,
                    onLeftMarkTap: leftMark.flatMap { m in onCommentMarkTap.map { handler in { handler(m) } } },
                    onRightMarkTap: rightMark.flatMap { m in onCommentMarkTap.map { handler in { handler(m) } } },
                    onCreateLeftComment: createCommentClosure(line: leftLine, side: .oldFile),
                    onCreateRightComment: createCommentClosure(line: rightLine, side: .newFile),
                    isLeftInSelection: isLineSelected(leftLine, side: .oldFile),
                    isRightInSelection: isLineSelected(rightLine, side: .newFile),
                    coordinateSpace: FolioSelectionMath.coordinateSpaceName
                )
            }
        }
    }

    private func unifiedIntralineRanges(_ visible: [DiffLine]) -> [Int: [NSRange]] {
        var result: [Int: [NSRange]] = [:]
        var pendingDeletions: [(idx: Int, line: DiffLine)] = []
        var pendingAdditions: [(idx: Int, line: DiffLine)] = []

        func flush() {
            let pairs = min(pendingDeletions.count, pendingAdditions.count)
            for i in 0..<pairs {
                let (delIdx, delLine) = pendingDeletions[i]
                let (addIdx, addLine) = pendingAdditions[i]
                let diff = IntralineDiff.compute(old: delLine.text, new: addLine.text)
                result[delIdx] = diff.oldRanges
                result[addIdx] = diff.newRanges
            }
            pendingDeletions.removeAll(keepingCapacity: true)
            pendingAdditions.removeAll(keepingCapacity: true)
        }

        for (i, line) in visible.enumerated() {
            switch line.kind {
            case .deletion: pendingDeletions.append((i, line))
            case .addition: pendingAdditions.append((i, line))
            case .context, .noNewline: flush()
            }
        }
        flush()
        return result
    }

    private func splitRowRangesAbsolute(
        rows: [SplitRow],
        lineRanges: [NSRange],
        visible: [DiffLine],
        baseIndex: Int
    ) -> [SplitLineRanges] {
        var indexByLine: [DiffLine: Int] = [:]
        for (i, line) in visible.enumerated() {
            indexByLine[line] = baseIndex + i
        }
        return rows.map { row in
            var pair = SplitLineRanges()
            if let line = row.left, let i = indexByLine[line], i < lineRanges.count {
                pair.leftRange = lineRanges[i]
            }
            if let line = row.right, let i = indexByLine[line], i < lineRanges.count {
                pair.rightRange = lineRanges[i]
            }
            return pair
        }
    }

    private func expand(direction: ExpandDirection, bounds: SnippetBounds) {
        switch direction {
        case .up:
            if bounds.linesAbove > 0 {
                contextAbove += min(expandStep, bounds.linesAbove + expandStep)
            } else {
                onExpandContext?(.up)
            }
        case .down:
            if bounds.linesBelow > 0 {
                contextBelow += min(expandStep, bounds.linesBelow + expandStep)
            } else {
                onExpandContext?(.down)
            }
        }
    }

    @ViewBuilder
    private func codeBody(text: String, startLine: Int) -> some View {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let highlighter = FolioHighlighter(theme: theme)
        let language = CodeLanguageRegistry.detect(path: path)
        let runs = highlighter.runs(for: text, language: language)
        let codeLineRanges = codeLineRanges(lines: lines)
        let gutter = codeGutterWidth(lineCount: lines.count, startLine: startLine)

        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, lineText in
                let lineNum = startLine + index
                let mark = findMark(side: .newFile, line: lineNum)
                CodeFolioRow(
                    lineNumber: lineNum,
                    text: lineText,
                    lineRange: codeLineRanges[index],
                    runs: runs,
                    theme: theme,
                    gutterWidth: gutter,
                    commentMark: mark,
                    onCommentMarkTap: mark.flatMap { m in onCommentMarkTap.map { handler in { handler(m) } } },
                    onCreateComment: createCommentClosure(line: lineNum, side: .newFile),
                    isInSelection: isLineSelected(lineNum, side: .newFile),
                    coordinateSpace: FolioSelectionMath.coordinateSpaceName
                )
            }
        }
    }

    private struct UnifiedLookup {
        let mark: FolioCommentMark?
        let side: AnchorRange.Side
        let lineNum: Int?
    }

    private func unifiedLookup(for line: DiffLine) -> UnifiedLookup {
        switch line.kind {
        case .addition:
            let n = line.newNumber
            return UnifiedLookup(
                mark: n.flatMap { findMark(side: .newFile, line: $0) },
                side: .newFile,
                lineNum: n
            )
        case .deletion:
            let o = line.oldNumber
            return UnifiedLookup(
                mark: o.flatMap { findMark(side: .oldFile, line: $0) },
                side: .oldFile,
                lineNum: o
            )
        case .context:
            if let n = line.newNumber, let m = findMark(side: .newFile, line: n) {
                return UnifiedLookup(mark: m, side: .newFile, lineNum: n)
            }
            if let o = line.oldNumber, let m = findMark(side: .oldFile, line: o) {
                return UnifiedLookup(mark: m, side: .oldFile, lineNum: o)
            }
            return UnifiedLookup(mark: nil, side: .newFile, lineNum: line.newNumber ?? line.oldNumber)
        case .noNewline:
            return UnifiedLookup(mark: nil, side: .newFile, lineNum: nil)
        }
    }

    private func findMark(side: AnchorRange.Side, line: Int) -> FolioCommentMark? {
        commentMarks.first { $0.side == side && $0.line == line }
    }

    private func createCommentClosure(line: Int?, side: AnchorRange.Side) -> (() -> Void)? {
        guard let line, let onCreateComment else { return nil }
        return { onCreateComment(line, side) }
    }

    private var effectiveSelection: FolioLineSelection? {
        selection?.wrappedValue ?? draftSelection
    }

    private var selectionDragGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(FolioSelectionMath.coordinateSpaceName))
            .onChanged { value in
                let updated = FolioSelectionMath.selection(
                    from: value.startLocation,
                    to: value.location,
                    cells: selectionCells
                )
                draftSelection = updated
            }
            .onEnded { value in
                let final = FolioSelectionMath.selection(
                    from: value.startLocation,
                    to: value.location,
                    cells: selectionCells
                )
                draftSelection = final
                selection?.wrappedValue = final
                onLineSelectionChange?(final)
            }
    }

    private func isLineSelected(_ line: Int?, side: AnchorRange.Side) -> Bool {
        guard let line, let sel = effectiveSelection, sel.side == side else { return false }
        return sel.contains(line)
    }

    private struct SplitLineRanges {
        var leftRange: NSRange?
        var rightRange: NSRange?
    }

    private func codeLineRanges(lines: [String]) -> [NSRange] {
        var ranges: [NSRange] = []
        var cursor = 0
        for line in lines {
            let length = (line as NSString).length
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

    private func codeGutterWidth(lineCount: Int, startLine: Int) -> CGFloat {
        let last = startLine + max(0, lineCount - 1)
        let widest = max(String(last).count, 3)
        return CGFloat(widest) * 7 + 4
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
