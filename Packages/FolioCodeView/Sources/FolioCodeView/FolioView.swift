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
    public let threadSlot: ((FolioCommentMark) -> AnyView)?
    public let composerSlot: FolioComposerSlot?
    public let isExpandable: Bool
    public let roundsBottomCorners: Bool
    public let editable: Bool
    public let text: Binding<String>?

    @State private var isExpanded: Bool = true
    @State private var contextAbove: Int
    @State private var contextBelow: Int
    @State private var selectionCells: [FolioSelectableCell] = []
    @State private var draftSelection: FolioLineSelection?
    @State private var gapStates: [Int: GapRevealState] = [:]
    @State private var artifact: FolioRenderArtifact
    @State private var commentMarkIndex: FolioCommentMarkIndex
    @State private var capExpanded: Bool = false

    private let expandStep: Int = 10
    private let gapExpandStep: Int = 20
    private let progressiveCap: Int = 800

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
        onLineSelectionChange: ((FolioLineSelection?) -> Void)? = nil,
        threadSlot: ((FolioCommentMark) -> AnyView)? = nil,
        composerSlot: FolioComposerSlot? = nil,
        isExpandable: Bool = true,
        contextLinesBelow: Int? = nil,
        roundsBottomCorners: Bool = true,
        editable: Bool = false,
        text: Binding<String>? = nil
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
        self.threadSlot = threadSlot
        self.composerSlot = composerSlot
        self.isExpandable = isExpandable
        self.roundsBottomCorners = roundsBottomCorners
        self.editable = editable
        self.text = text
        self._contextAbove = State(initialValue: contextLines)
        self._contextBelow = State(initialValue: contextLinesBelow ?? contextLines)
        self._isExpanded = State(initialValue: !showsHeader || true)
        self._artifact = State(initialValue: FolioRenderArtifactBuilder.skeleton(
            content: content,
            contextLines: contextLines
        ))
        self._commentMarkIndex = State(initialValue: FolioCommentMarkIndex(commentMarks))
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
                rowContainer
            }
        }
        .background(Color(theme.contextRow.withAlpha(1)))
        .overlay {
            folioShape.strokeBorder(Color(theme.border), lineWidth: 1)
        }
        .clipShape(folioShape)
        .task(id: artifactKey) {
            await refreshArtifact()
        }
        .onChange(of: commentMarks) { _, marks in
            commentMarkIndex = FolioCommentMarkIndex(marks)
        }
    }

    private var folioShape: UnevenRoundedRectangle {
        let bottomRadius = roundsBottomCorners ? cornerRadius : 0
        return UnevenRoundedRectangle(
            topLeadingRadius: cornerRadius,
            bottomLeadingRadius: bottomRadius,
            bottomTrailingRadius: bottomRadius,
            topTrailingRadius: cornerRadius,
            style: .continuous
        )
    }

    private var artifactKey: Int {
        var hasher = Hasher()
        hasher.combine(path)
        hasher.combine(theme.paletteSignature)
        hasher.combine(initialContextLines)
        switch content {
        case let .diff(hunk, _, _):
            hasher.combine(0)
            hasher.combine(hunk.oldStart)
            hasher.combine(hunk.newStart)
            hasher.combine(hunk.lines.count)
            hasher.combine(hunk.lines.first?.text)
            hasher.combine(hunk.lines.last?.text)
        case let .code(text, startLine):
            hasher.combine(1)
            hasher.combine(text.count)
            hasher.combine(text.first)
            hasher.combine(text.last)
            hasher.combine(startLine)
        }
        return hasher.finalize()
    }

    @MainActor
    private func refreshArtifact() async {
        let path = self.path
        let content = self.content
        let theme = self.theme
        let contextLines = self.initialContextLines

        let full = await Task.detached(priority: .userInitiated) {
            let key = FolioRenderArtifactCacheKey(
                content: content,
                path: path,
                theme: theme,
                contextLines: contextLines
            )
            if let cached = await FolioRenderArtifactCache.shared.artifact(for: key) {
                return cached
            }
            let artifact = FolioRenderArtifactBuilder.full(
                content: content,
                contextLines: contextLines,
                path: path,
                theme: theme
            )
            await FolioRenderArtifactCache.shared.store(artifact, for: key)
            return artifact
        }.value
        guard !Task.isCancelled else { return }
        artifact = full
    }

    private var header: some View {
        HStack(spacing: 6) {
            Button {
                isExpanded.toggle()
            } label: {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .scaledFont(.caption2)
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

    private var selectionReportingEnabled: Bool {
        selection != nil || onLineSelectionChange != nil
    }

    @ViewBuilder
    private var pathButton: some View {
        if let onPathTap {
            Button(action: onPathTap) {
                Text(path)
                    .scaledFont(.caption, weight: .semibold, design: .monospaced)
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
                .scaledFont(.caption, weight: .semibold, design: .monospaced)
                .lineLimit(1)
                .truncationMode(.head)
        }
    }

    private var outdatedBadge: some View {
        Text("Outdated")
            .scaledFont(.caption2, weight: .semibold)
            .foregroundColor(.orange)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .overlay(
                Capsule().strokeBorder(Color.orange, lineWidth: 1)
            )
    }

    @ViewBuilder
    private var rows: some View {
        switch (artifact.kind, content) {
        case let (.diff(diff), .diff(_, anchor, mode)):
            if let anchor {
                anchoredDiffBody(diff: diff, anchor: anchor, mode: mode)
            } else {
                foldedDiffBody(diff: diff, mode: mode)
            }
        case let (.code(code), .code(_, startLine)):
            if editable {
                editableCodeBody(startLine: startLine)
            } else {
                codeBody(code: code)
            }
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var rowContainer: some View {
        if selectionReportingEnabled {
            #if os(macOS)
            rows
                .coordinateSpace(name: FolioSelectionMath.coordinateSpaceName)
                .gesture(selectionDragGesture)
                .onPreferenceChange(FolioSelectableCellsPreference.self) { cells in
                    selectionCells = cells
                }
            #else
            rows
                .coordinateSpace(name: FolioSelectionMath.coordinateSpaceName)
                .onPreferenceChange(FolioSelectableCellsPreference.self) { cells in
                    selectionCells = cells
                }
            #endif
        } else {
            rows
                .coordinateSpace(name: FolioSelectionMath.coordinateSpaceName)
        }
    }

    @ViewBuilder
    private func editableCodeBody(startLine: Int) -> some View {
        if let text {
            CodeBlockView(
                text: text,
                language: CodeLanguageRegistry.detect(path: path),
                startLine: startLine,
                theme: theme,
                showsLineNumbers: true
            )
        } else {
            #if DEBUG
            Color.clear.onAppear {
                assertionFailure("FolioView(editable: true) requires text: Binding<String>")
            }
            #else
            EmptyView()
            #endif
        }
    }

    @ViewBuilder
    private func anchoredDiffBody(
        diff: FolioRenderArtifact.Diff,
        anchor: AnchorRange,
        mode: DiffViewMode
    ) -> some View {
        let bounds = SnippetWindow.bounds(
            hunk: diff.hunk,
            anchor: anchor,
            contextAbove: contextAbove,
            contextBelow: contextBelow
        )
        let leadingGutter = artifact.gutterWidth + 8
        let trailingGutter: CGFloat? = mode == .split ? leadingGutter : nil

        VStack(alignment: .leading, spacing: 0) {
            if isExpandable, bounds.linesAbove > 0 || onExpandContext != nil {
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
            if !bounds.isEmpty {
                renderRowRange(
                    diff: diff,
                    range: bounds.startIndex...bounds.endIndex,
                    mode: mode
                )
            }
            if isExpandable, bounds.linesBelow > 0 || onExpandContext != nil {
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

    private func computeGapPositions(_ sections: [FoldedDiff.Section]) -> [GapPosition] {
        var hasLinesBefore = Array(repeating: false, count: sections.count)
        var hasLinesAfter = Array(repeating: false, count: sections.count)
        var seen = false
        for i in 0..<sections.count {
            hasLinesBefore[i] = seen
            if case .lines = sections[i] { seen = true }
        }
        seen = false
        for i in stride(from: sections.count - 1, through: 0, by: -1) {
            hasLinesAfter[i] = seen
            if case .lines = sections[i] { seen = true }
        }
        return (0..<sections.count).map { i in
            switch (hasLinesBefore[i], hasLinesAfter[i]) {
            case (false, true): return .leading
            case (true, false): return .trailing
            case (true, true): return .middle
            case (false, false): return .standalone
            }
        }
    }

    @ViewBuilder
    private func foldedDiffBody(
        diff: FolioRenderArtifact.Diff,
        mode: DiffViewMode
    ) -> some View {
        let leadingGutter = artifact.gutterWidth + 8
        let trailingGutter: CGFloat? = mode == .split ? leadingGutter : nil
        let sections = diff.foldedSections
        let positions = computeGapPositions(sections)
        let capInfo = progressiveCapInfo(for: sections)

        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(sections.enumerated()), id: \.offset) { idx, section in
                if let capInfo, idx > capInfo.cutSectionIdx {
                    EmptyView()
                } else {
                    switch section {
                    case let .lines(start, end):
                        let cappedEnd = (capInfo?.cutSectionIdx == idx) ? capInfo!.cappedEnd : end
                        if cappedEnd >= start {
                            renderRowRange(
                                diff: diff,
                                range: start...cappedEnd,
                                mode: mode
                            )
                        }
                        if let capInfo, capInfo.cutSectionIdx == idx {
                            progressiveCapRow(
                                hidden: capInfo.hiddenLineCount,
                                leadingGutter: leadingGutter,
                                trailingGutter: trailingGutter
                            )
                        }
                    case let .gap(start, end):
                        foldedGap(
                            idx: idx,
                            start: start,
                            end: end,
                            position: positions[idx],
                            diff: diff,
                            leadingGutter: leadingGutter,
                            trailingGutter: trailingGutter,
                            mode: mode
                        )
                    }
                }
            }
        }
    }

    private struct ProgressiveCapInfo {
        let cutSectionIdx: Int
        let cappedEnd: Int
        let hiddenLineCount: Int
    }

    private func progressiveCapInfo(for sections: [FoldedDiff.Section]) -> ProgressiveCapInfo? {
        if capExpanded { return nil }
        var totalLines = 0
        for s in sections {
            if case let .lines(start, end) = s {
                totalLines += end - start + 1
            }
        }
        guard totalLines > progressiveCap else { return nil }

        var soFar = 0
        for (i, s) in sections.enumerated() {
            guard case let .lines(start, end) = s else { continue }
            let size = end - start + 1
            if soFar + size <= progressiveCap {
                soFar += size
                continue
            }
            let remaining = progressiveCap - soFar
            let cappedEnd = remaining > 0 ? start + remaining - 1 : start - 1
            var hiddenInLater = 0
            for j in (i + 1)..<sections.count {
                if case let .lines(s2, e2) = sections[j] {
                    hiddenInLater += e2 - s2 + 1
                }
            }
            return ProgressiveCapInfo(
                cutSectionIdx: i,
                cappedEnd: cappedEnd,
                hiddenLineCount: (end - cappedEnd) + hiddenInLater
            )
        }
        return nil
    }

    @ViewBuilder
    private func progressiveCapRow(
        hidden: Int,
        leadingGutter: CGFloat,
        trailingGutter: CGFloat?
    ) -> some View {
        ExpandContextRow(
            label: hidden == 1
                ? "Show 1 more line"
                : "Show \(hidden) more lines",
            theme: theme,
            leadingGutterWidth: leadingGutter,
            trailingGutterWidth: trailingGutter,
            onExpandFromTop: {
                withAnimation(.snappy(duration: 0.18)) {
                    capExpanded = true
                }
            }
        )
    }

    @ViewBuilder
    private func foldedGap(
        idx: Int,
        start: Int,
        end: Int,
        position: GapPosition,
        diff: FolioRenderArtifact.Diff,
        leadingGutter: CGFloat,
        trailingGutter: CGFloat?,
        mode: DiffViewMode
    ) -> some View {
        let state = gapStates[start] ?? GapRevealState()
        let totalSize = end - start + 1
        let revealed = state.revealedFromTop + state.revealedFromBottom
        let hiddenCount = max(0, totalSize - revealed)

        Group {
            if revealed >= totalSize {
                renderRowRange(
                    diff: diff,
                    range: start...end,
                    mode: mode
                )
            } else {
                if state.revealedFromTop > 0 {
                    renderRowRange(
                        diff: diff,
                        range: start...(start + state.revealedFromTop - 1),
                        mode: mode
                    )
                }
                ExpandContextRow(
                    label: ExpandContextRow.unmodifiedLabel(count: hiddenCount),
                    theme: theme,
                    leadingGutterWidth: leadingGutter,
                    trailingGutterWidth: trailingGutter,
                    onExpandFromTop: (position == .leading) ? nil : {
                        withAnimation(.snappy(duration: 0.18)) {
                            expandGap(start: start, totalSize: totalSize, fromTop: true)
                        }
                    },
                    onExpandFromBottom: (position == .trailing) ? nil : {
                        withAnimation(.snappy(duration: 0.18)) {
                            expandGap(start: start, totalSize: totalSize, fromTop: false)
                        }
                    }
                )
                if state.revealedFromBottom > 0 {
                    renderRowRange(
                        diff: diff,
                        range: (end - state.revealedFromBottom + 1)...end,
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

    @ViewBuilder
    private func renderRowRange(
        diff: FolioRenderArtifact.Diff,
        range: ClosedRange<Int>,
        mode: DiffViewMode
    ) -> some View {
        let hunk = diff.hunk
        if !range.isEmpty,
           range.lowerBound >= 0,
           range.upperBound < hunk.lines.count {
            switch mode {
            case .unified:
                ForEach(range, id: \.self) { absIdx in
                    let line = hunk.lines[absIdx]
                    let lookup = unifiedLookup(for: line)
                    FolioRow(
                        line: line,
                        lineRange: diff.lineRanges[absIdx],
                        runs: lineRuns(in: diff, index: absIdx),
                        theme: theme,
                        gutterWidth: artifact.gutterWidth,
                        commentMark: lookup.mark,
                        onCommentMarkTap: lookup.mark.flatMap { m in
                            onCommentMarkTap.map { handler in { handler(m) } }
                        },
                        onCreateComment: createCommentClosure(line: lookup.lineNum, side: lookup.side),
                        isInSelection: isLineSelected(lookup.lineNum, side: lookup.side),
                        coordinateSpace: FolioSelectionMath.coordinateSpaceName,
                        reportsSelection: selectionReportingEnabled,
                        intralineRanges: diff.unifiedIntralineByHunkIdx[absIdx] ?? []
                    )
                    unifiedSlots(for: line)
                }
            case .split:
                let cache = diff.intralineDiffByText
                let splitRows = SplitRowBuilder.build(hunk.lines[range]) { old, new in
                    cache[FolioTextPair(old: old, new: new)]
                }
                ForEach(Array(splitRows.enumerated()), id: \.offset) { _, row in
                    let leftAbs = row.leftIndex
                    let rightAbs = row.rightIndex
                    let leftLineRange = leftAbs.flatMap { i -> NSRange? in
                        i < diff.lineRanges.count ? diff.lineRanges[i] : nil
                    }
                    let rightLineRange = rightAbs.flatMap { i -> NSRange? in
                        i < diff.lineRanges.count ? diff.lineRanges[i] : nil
                    }
                    let leftLineNum = row.left?.oldNumber
                    let rightLineNum = row.right?.newNumber
                    let leftMark = leftLineNum.flatMap { findMark(side: .oldFile, line: $0) }
                    let rightMark = rightLineNum.flatMap { findMark(side: .newFile, line: $0) }
                    SplitFolioRow(
                        row: row,
                        leftLineRange: leftLineRange,
                        rightLineRange: rightLineRange,
                        runs: splitRuns(in: diff, left: leftAbs, right: rightAbs),
                        theme: theme,
                        gutterWidth: artifact.gutterWidth,
                        leftMark: leftMark,
                        rightMark: rightMark,
                        onLeftMarkTap: leftMark.flatMap { m in
                            onCommentMarkTap.map { handler in { handler(m) } }
                        },
                        onRightMarkTap: rightMark.flatMap { m in
                            onCommentMarkTap.map { handler in { handler(m) } }
                        },
                        onCreateLeftComment: createCommentClosure(line: leftLineNum, side: .oldFile),
                        onCreateRightComment: createCommentClosure(line: rightLineNum, side: .newFile),
                        isLeftInSelection: isLineSelected(leftLineNum, side: .oldFile),
                        isRightInSelection: isLineSelected(rightLineNum, side: .newFile),
                        coordinateSpace: FolioSelectionMath.coordinateSpaceName,
                        reportsSelection: selectionReportingEnabled
                    )
                    splitSlots(for: row)
                }
            }
        }
    }

    private func lineRuns(
        in diff: FolioRenderArtifact.Diff,
        index: Int?
    ) -> [FolioHighlighter.Run] {
        guard let index,
              index >= 0,
              index < diff.runsByLine.count else {
            return []
        }
        return diff.runsByLine[index]
    }

    private func splitRuns(
        in diff: FolioRenderArtifact.Diff,
        left: Int?,
        right: Int?
    ) -> [FolioHighlighter.Run] {
        if left == right {
            return lineRuns(in: diff, index: left)
        }
        return lineRuns(in: diff, index: left) + lineRuns(in: diff, index: right)
    }

    @ViewBuilder
    private func unifiedSlots(for line: DiffLine) -> some View {
        switch line.kind {
        case .addition:
            if let n = line.newNumber {
                slotsAt(side: .newFile, line: n)
            }
        case .deletion:
            if let o = line.oldNumber {
                slotsAt(side: .oldFile, line: o)
            }
        case .context:
            if let n = line.newNumber {
                slotsAt(side: .newFile, line: n)
            }
            if let o = line.oldNumber {
                slotsAt(side: .oldFile, line: o)
            }
        case .noNewline:
            EmptyView()
        }
    }

    @ViewBuilder
    private func splitSlots(for row: SplitRow) -> some View {
        let leftLine = row.left?.oldNumber
        let rightLine = row.right?.newNumber
        if hasSlot(side: .oldFile, line: leftLine) || hasSlot(side: .newFile, line: rightLine) {
            HStack(alignment: .top, spacing: 0) {
                HStack(spacing: 0) {
                    if let leftLine, hasSlot(side: .oldFile, line: leftLine) {
                        slotsAt(side: .oldFile, line: leftLine)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Color.clear.frame(width: 1)

                HStack(spacing: 0) {
                    if let rightLine, hasSlot(side: .newFile, line: rightLine) {
                        slotsAt(side: .newFile, line: rightLine)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func hasSlot(side: AnchorRange.Side, line: Int?) -> Bool {
        guard let line else { return false }
        if threadSlot != nil, findMark(side: side, line: line) != nil { return true }
        if let composerSlot, composerSlot.side == side, composerSlot.line == line { return true }
        return false
    }

    @ViewBuilder
    private func slotsAt(side: AnchorRange.Side, line: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let threadSlot, let mark = findMark(side: side, line: line) {
                threadSlot(mark)
            }
            if let composerSlot, composerSlot.line == line, composerSlot.side == side {
                composerSlot.content()
            }
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
    private func codeBody(code: FolioRenderArtifact.Code) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(code.lines.enumerated()), id: \.offset) { index, lineText in
                let lineNum = code.startLine + index
                let mark = findMark(side: .newFile, line: lineNum)
                CodeFolioRow(
                    lineNumber: lineNum,
                    text: lineText,
                    lineRange: code.lineRanges[index],
                    runs: code.runsByLine[index],
                    theme: theme,
                    gutterWidth: artifact.gutterWidth,
                    commentMark: mark,
                    onCommentMarkTap: mark.flatMap { m in
                        onCommentMarkTap.map { handler in { handler(m) } }
                    },
                    onCreateComment: createCommentClosure(line: lineNum, side: .newFile),
                    isInSelection: isLineSelected(lineNum, side: .newFile),
                    coordinateSpace: FolioSelectionMath.coordinateSpaceName,
                    reportsSelection: selectionReportingEnabled
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
        commentMarkIndex.mark(side: side, line: line)
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
