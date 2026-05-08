import Foundation
import FolioModel
import FolioHighlight

struct FolioTextPair: Sendable, Hashable {
    let old: String
    let new: String
}

struct FolioRenderArtifact: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case diff(Diff)
        case code(Code)
        case empty
    }

    struct Diff: Sendable, Equatable {
        let hunk: DiffHunk
        let lineRanges: [NSRange]
        let runsByLine: [[FolioHighlighter.Run]]
        let intralineDiffByText: [FolioTextPair: IntralineDiff.Result]
        let unifiedIntralineByHunkIdx: [Int: [NSRange]]
        let splitRows: [SplitRowDescriptor]
        let foldedSections: [FoldedDiff.Section]
        let foldedContextLines: Int
    }

    struct SplitRowDescriptor: Sendable, Equatable {
        let leftIndex: Int?
        let rightIndex: Int?
        let intralineDiff: IntralineDiff.Result?

        func clipped(to range: ClosedRange<Int>) -> SplitRowDescriptor? {
            let clippedLeft = leftIndex.flatMap { range.contains($0) ? $0 : nil }
            let clippedRight = rightIndex.flatMap { range.contains($0) ? $0 : nil }
            guard clippedLeft != nil || clippedRight != nil else { return nil }
            return SplitRowDescriptor(
                leftIndex: clippedLeft,
                rightIndex: clippedRight,
                intralineDiff: clippedLeft != nil && clippedRight != nil ? intralineDiff : nil
            )
        }
    }

    struct Code: Sendable, Equatable {
        let text: String
        let lineRanges: [NSRange]
        let runsByLine: [[FolioHighlighter.Run]]
        let startLine: Int

        func lineText(at index: Int) -> String {
            guard lineRanges.indices.contains(index) else { return "" }
            return (text as NSString).substring(with: lineRanges[index])
        }
    }

    let kind: Kind
    let gutterWidth: CGFloat

    static let empty = FolioRenderArtifact(
        kind: .empty,
        gutterWidth: 30
    )

    var totalLineCount: Int {
        switch kind {
        case let .diff(d): return d.hunk.lines.count
        case let .code(c): return c.lineRanges.count
        case .empty: return 0
        }
    }

    var estimatedByteCost: Int {
        switch kind {
        case let .diff(diff):
            return 128
                + estimatedCost(of: diff.hunk)
                + estimatedCost(of: diff.lineRanges)
                + estimatedCost(of: diff.runsByLine)
                + estimatedCost(of: diff.intralineDiffByText)
                + estimatedCost(of: diff.unifiedIntralineByHunkIdx)
                + estimatedCost(of: diff.splitRows)
                + diff.foldedSections.count * 32
        case let .code(code):
            return 128
                + estimatedCost(of: code.text)
                + estimatedCost(of: code.lineRanges)
                + estimatedCost(of: code.runsByLine)
        case .empty:
            return 64
        }
    }
}

private func estimatedCost(of hunk: DiffHunk) -> Int {
    hunk.lines.reduce(64) { total, line in
        total + 48 + estimatedCost(of: line.text)
    }
}

private func estimatedCost(of string: String) -> Int {
    32 + string.utf8.count
}

private func estimatedCost(of ranges: [NSRange]) -> Int {
    24 + ranges.count * MemoryLayout<NSRange>.stride
}

private func estimatedCost(of runsByLine: [[FolioHighlighter.Run]]) -> Int {
    runsByLine.reduce(24 + runsByLine.count * 24) { total, runs in
        total + runs.count * MemoryLayout<FolioHighlighter.Run>.stride
    }
}

private func estimatedCost(of cache: [FolioTextPair: IntralineDiff.Result]) -> Int {
    cache.reduce(24) { total, entry in
        total
            + 96
            + estimatedCost(of: entry.key.old)
            + estimatedCost(of: entry.key.new)
            + estimatedCost(of: entry.value.oldRanges)
            + estimatedCost(of: entry.value.newRanges)
    }
}

private func estimatedCost(of intralineByIndex: [Int: [NSRange]]) -> Int {
    intralineByIndex.reduce(24) { total, entry in
        total + 32 + estimatedCost(of: entry.value)
    }
}

private func estimatedCost(of splitRows: [FolioRenderArtifact.SplitRowDescriptor]) -> Int {
    splitRows.reduce(24) { total, row in
        total
            + 32
            + (row.intralineDiff.map {
                estimatedCost(of: $0.oldRanges) + estimatedCost(of: $0.newRanges)
            } ?? 0)
    }
}

enum FolioRenderArtifactBuilder {
    static let highlightUTF16Limit = 250_000

    static func skeleton(
        content: FolioContent,
        contextLines: Int
    ) -> FolioRenderArtifact {
        switch content {
        case let .diff(hunk, _, _):
            let lineRanges = makeLineRanges(for: hunk.lines)
            let folded = DiffFolder.fold(hunk, contextLines: contextLines).sections
            let gutter = makeGutterWidth(for: hunk.lines[...])
            return FolioRenderArtifact(
                kind: .diff(.init(
                    hunk: hunk,
                    lineRanges: lineRanges,
                    runsByLine: Array(repeating: [], count: lineRanges.count),
                    intralineDiffByText: [:],
                    unifiedIntralineByHunkIdx: [:],
                    splitRows: makeSplitRows(for: hunk.lines, cache: [:]),
                    foldedSections: folded,
                    foldedContextLines: contextLines
                )),
                gutterWidth: gutter
            )
        case let .code(text, startLine):
            let lineRanges = makeCodeLineRanges(text: text)
            let gutter = makeCodeGutterWidth(lineCount: lineRanges.count, startLine: startLine)
            return FolioRenderArtifact(
                kind: .code(.init(
                    text: text,
                    lineRanges: lineRanges,
                    runsByLine: Array(repeating: [], count: lineRanges.count),
                    startLine: startLine
                )),
                gutterWidth: gutter
            )
        }
    }

    static func full(
        content: FolioContent,
        contextLines: Int,
        path: String,
        theme: HighlightTheme
    ) -> FolioRenderArtifact {
        switch content {
        case let .diff(hunk, _, _):
            let lineRanges = makeLineRanges(for: hunk.lines)
            let intralineCache = makeIntralineCache(for: hunk.lines)
            let unifiedIntraline = makeUnifiedIntralineByHunkIdx(for: hunk.lines, cache: intralineCache)
            let folded = DiffFolder.fold(hunk, contextLines: contextLines).sections
            let gutter = makeGutterWidth(for: hunk.lines[...])
            let runs = computeRuns(path: path, content: content, theme: theme)
            return FolioRenderArtifact(
                kind: .diff(.init(
                    hunk: hunk,
                    lineRanges: lineRanges,
                    runsByLine: makeRunsByLine(runs: runs, lineRanges: lineRanges),
                    intralineDiffByText: intralineCache,
                    unifiedIntralineByHunkIdx: unifiedIntraline,
                    splitRows: makeSplitRows(for: hunk.lines, cache: intralineCache),
                    foldedSections: folded,
                    foldedContextLines: contextLines
                )),
                gutterWidth: gutter
            )
        case let .code(text, startLine):
            let lineRanges = makeCodeLineRanges(text: text)
            let gutter = makeCodeGutterWidth(lineCount: lineRanges.count, startLine: startLine)
            let runs = computeRuns(path: path, content: content, theme: theme)
            return FolioRenderArtifact(
                kind: .code(.init(
                    text: text,
                    lineRanges: lineRanges,
                    runsByLine: makeRunsByLine(runs: runs, lineRanges: lineRanges),
                    startLine: startLine
                )),
                gutterWidth: gutter
            )
        }
    }

    static func computeRuns(
        path: String,
        content: FolioContent,
        theme: HighlightTheme
    ) -> [FolioHighlighter.Run] {
        let language = CodeLanguageRegistry.detect(path: path)
        guard language.id != CodeLanguage.plain.id else { return [] }
        let highlighter = FolioHighlighter(theme: theme)
        switch content {
        case let .diff(hunk, _, _):
            guard diffTextLength(hunk.lines) <= highlightUTF16Limit else { return [] }
            let corpus = hunk.lines.map(\.text).joined(separator: "\n")
            return highlighter.runs(for: corpus, language: language)
        case let .code(text, _):
            guard (text as NSString).length <= highlightUTF16Limit else { return [] }
            return highlighter.runs(for: text, language: language)
        }
    }

    private static func diffTextLength(_ lines: [DiffLine]) -> Int {
        guard !lines.isEmpty else { return 0 }
        let textLength = lines.reduce(0) { $0 + ($1.text as NSString).length }
        return textLength + lines.count - 1
    }

    private static func makeLineRanges(for lines: [DiffLine]) -> [NSRange] {
        var ranges: [NSRange] = []
        ranges.reserveCapacity(lines.count)
        var cursor = 0
        for line in lines {
            let length = (line.text as NSString).length
            ranges.append(NSRange(location: cursor, length: length))
            cursor += length + 1
        }
        return ranges
    }

    private static func makeCodeLineRanges(text: String) -> [NSRange] {
        let nsText = text as NSString
        let length = nsText.length
        guard length > 0 else { return [] }
        var ranges: [NSRange] = []
        var lineStart = 0
        var index = 0
        while index < length {
            if nsText.character(at: index) == 0x0A {
                ranges.append(NSRange(location: lineStart, length: index - lineStart))
                lineStart = index + 1
            }
            index += 1
        }
        ranges.append(NSRange(location: lineStart, length: length - lineStart))
        return ranges
    }

    private static func makeRunsByLine(
        runs: [FolioHighlighter.Run],
        lineRanges: [NSRange]
    ) -> [[FolioHighlighter.Run]] {
        var runsByLine = Array(repeating: [FolioHighlighter.Run](), count: lineRanges.count)
        guard !runs.isEmpty, !lineRanges.isEmpty else { return runsByLine }

        let sortedRuns = runs.sorted {
            if $0.range.location == $1.range.location {
                return $0.range.length < $1.range.length
            }
            return $0.range.location < $1.range.location
        }
        var lineIndex = 0

        for run in sortedRuns {
            let runStart = run.range.location
            let runEnd = run.range.location + run.range.length
            while lineIndex < lineRanges.count {
                let lineRange = lineRanges[lineIndex]
                let lineEnd = lineRange.location + lineRange.length
                if lineEnd > runStart { break }
                lineIndex += 1
            }

            var idx = lineIndex
            while idx < lineRanges.count {
                let lineRange = lineRanges[idx]
                if lineRange.location >= runEnd { break }
                if NSIntersectionRange(run.range, lineRange).length > 0 {
                    runsByLine[idx].append(run)
                }
                idx += 1
            }
        }

        return runsByLine
    }

    private static func makeIntralineCache(for lines: [DiffLine]) -> [FolioTextPair: IntralineDiff.Result] {
        var cache: [FolioTextPair: IntralineDiff.Result] = [:]
        var pendingDel: [DiffLine] = []
        var pendingAdd: [DiffLine] = []

        func flush() {
            let pairs = min(pendingDel.count, pendingAdd.count)
            for i in 0..<pairs {
                let key = FolioTextPair(old: pendingDel[i].text, new: pendingAdd[i].text)
                if cache[key] == nil {
                    cache[key] = IntralineDiff.compute(old: pendingDel[i].text, new: pendingAdd[i].text)
                }
            }
            pendingDel.removeAll(keepingCapacity: true)
            pendingAdd.removeAll(keepingCapacity: true)
        }

        for line in lines {
            switch line.kind {
            case .deletion: pendingDel.append(line)
            case .addition: pendingAdd.append(line)
            case .context, .noNewline: flush()
            }
        }
        flush()
        return cache
    }

    private static func makeUnifiedIntralineByHunkIdx(
        for lines: [DiffLine],
        cache: [FolioTextPair: IntralineDiff.Result]
    ) -> [Int: [NSRange]] {
        var result: [Int: [NSRange]] = [:]
        var pendingDel: [(idx: Int, line: DiffLine)] = []
        var pendingAdd: [(idx: Int, line: DiffLine)] = []

        func flush() {
            let pairs = min(pendingDel.count, pendingAdd.count)
            for i in 0..<pairs {
                let l = pendingDel[i]
                let r = pendingAdd[i]
                let key = FolioTextPair(old: l.line.text, new: r.line.text)
                guard let diff = cache[key] else { continue }
                result[l.idx] = diff.oldRanges
                result[r.idx] = diff.newRanges
            }
            pendingDel.removeAll(keepingCapacity: true)
            pendingAdd.removeAll(keepingCapacity: true)
        }

        for (i, line) in lines.enumerated() {
            switch line.kind {
            case .deletion: pendingDel.append((i, line))
            case .addition: pendingAdd.append((i, line))
            case .context, .noNewline: flush()
            }
        }
        flush()
        return result
    }

    private static func makeSplitRows(
        for lines: [DiffLine],
        cache: [FolioTextPair: IntralineDiff.Result]
    ) -> [FolioRenderArtifact.SplitRowDescriptor] {
        var rows: [FolioRenderArtifact.SplitRowDescriptor] = []
        var pendingDeletions: [Int] = []
        var pendingAdditions: [Int] = []

        func flush() {
            let pairs = max(pendingDeletions.count, pendingAdditions.count)
            for i in 0..<pairs {
                let leftIndex = i < pendingDeletions.count ? pendingDeletions[i] : nil
                let rightIndex = i < pendingAdditions.count ? pendingAdditions[i] : nil
                let diff: IntralineDiff.Result?
                if let leftIndex, let rightIndex {
                    diff = cache[FolioTextPair(
                        old: lines[leftIndex].text,
                        new: lines[rightIndex].text
                    )]
                } else {
                    diff = nil
                }
                rows.append(FolioRenderArtifact.SplitRowDescriptor(
                    leftIndex: leftIndex,
                    rightIndex: rightIndex,
                    intralineDiff: diff
                ))
            }
            pendingDeletions.removeAll(keepingCapacity: true)
            pendingAdditions.removeAll(keepingCapacity: true)
        }

        for (idx, line) in lines.enumerated() {
            switch line.kind {
            case .deletion:
                pendingDeletions.append(idx)
            case .addition:
                pendingAdditions.append(idx)
            case .context, .noNewline:
                flush()
                rows.append(FolioRenderArtifact.SplitRowDescriptor(
                    leftIndex: idx,
                    rightIndex: idx,
                    intralineDiff: nil
                ))
            }
        }
        flush()
        return rows
    }

    private static func makeGutterWidth(for visible: ArraySlice<DiffLine>) -> CGFloat {
        let widest = visible.reduce(0) { acc, line in
            let o = line.oldNumber.map { String($0).count } ?? 0
            let n = line.newNumber.map { String($0).count } ?? 0
            return max(acc, o, n)
        }
        return CGFloat(max(widest, 3)) * 7 + 4
    }

    private static func makeCodeGutterWidth(lineCount: Int, startLine: Int) -> CGFloat {
        let last = startLine + max(0, lineCount - 1)
        let widest = max(String(last).count, 3)
        return CGFloat(widest) * 7 + 4
    }
}
