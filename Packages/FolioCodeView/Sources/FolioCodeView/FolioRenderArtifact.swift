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
        let intralineDiffByText: [FolioTextPair: IntralineDiff.Result]
        let unifiedIntralineByHunkIdx: [Int: [NSRange]]
        let foldedSections: [FoldedDiff.Section]
        let foldedContextLines: Int
    }

    struct Code: Sendable, Equatable {
        let lines: [String]
        let lineRanges: [NSRange]
        let startLine: Int
    }

    let kind: Kind
    var runs: [FolioHighlighter.Run]
    let commentMarksByLine: [AnchorRange.Side: [Int: FolioCommentMark]]
    let gutterWidth: CGFloat

    static let empty = FolioRenderArtifact(
        kind: .empty,
        runs: [],
        commentMarksByLine: [:],
        gutterWidth: 30
    )

    var totalLineCount: Int {
        switch kind {
        case let .diff(d): return d.hunk.lines.count
        case let .code(c): return c.lines.count
        case .empty: return 0
        }
    }
}

enum FolioRenderArtifactBuilder {
    static func skeleton(
        content: FolioContent,
        marks: [FolioCommentMark],
        contextLines: Int
    ) -> FolioRenderArtifact {
        let marksByLine = makeMarksByLine(marks)
        switch content {
        case let .diff(hunk, _, _):
            let lineRanges = makeLineRanges(for: hunk.lines)
            let folded = DiffFolder.fold(hunk, contextLines: contextLines).sections
            let gutter = makeGutterWidth(for: hunk.lines[...])
            return FolioRenderArtifact(
                kind: .diff(.init(
                    hunk: hunk,
                    lineRanges: lineRanges,
                    intralineDiffByText: [:],
                    unifiedIntralineByHunkIdx: [:],
                    foldedSections: folded,
                    foldedContextLines: contextLines
                )),
                runs: [],
                commentMarksByLine: marksByLine,
                gutterWidth: gutter
            )
        case let .code(text, startLine):
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            let lineRanges = makeCodeLineRanges(lines: lines)
            let gutter = makeCodeGutterWidth(lineCount: lines.count, startLine: startLine)
            return FolioRenderArtifact(
                kind: .code(.init(
                    lines: lines,
                    lineRanges: lineRanges,
                    startLine: startLine
                )),
                runs: [],
                commentMarksByLine: marksByLine,
                gutterWidth: gutter
            )
        }
    }

    static func full(
        content: FolioContent,
        marks: [FolioCommentMark],
        contextLines: Int,
        path: String,
        theme: HighlightTheme
    ) -> FolioRenderArtifact {
        let marksByLine = makeMarksByLine(marks)
        switch content {
        case let .diff(hunk, _, _):
            let lineRanges = makeLineRanges(for: hunk.lines)
            let intralineCache = makeIntralineCache(for: hunk.lines)
            let unifiedIntraline = makeUnifiedIntralineByHunkIdx(for: hunk.lines, cache: intralineCache)
            let folded = DiffFolder.fold(hunk, contextLines: contextLines).sections
            let gutter = makeGutterWidth(for: hunk.lines[...])
            return FolioRenderArtifact(
                kind: .diff(.init(
                    hunk: hunk,
                    lineRanges: lineRanges,
                    intralineDiffByText: intralineCache,
                    unifiedIntralineByHunkIdx: unifiedIntraline,
                    foldedSections: folded,
                    foldedContextLines: contextLines
                )),
                runs: computeRuns(path: path, content: content, theme: theme),
                commentMarksByLine: marksByLine,
                gutterWidth: gutter
            )
        case let .code(text, startLine):
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            let lineRanges = makeCodeLineRanges(lines: lines)
            let gutter = makeCodeGutterWidth(lineCount: lines.count, startLine: startLine)
            return FolioRenderArtifact(
                kind: .code(.init(
                    lines: lines,
                    lineRanges: lineRanges,
                    startLine: startLine
                )),
                runs: computeRuns(path: path, content: content, theme: theme),
                commentMarksByLine: marksByLine,
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
            let corpus = hunk.lines.map(\.text).joined(separator: "\n")
            return highlighter.runs(for: corpus, language: language)
        case let .code(text, _):
            return highlighter.runs(for: text, language: language)
        }
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

    private static func makeCodeLineRanges(lines: [String]) -> [NSRange] {
        var ranges: [NSRange] = []
        ranges.reserveCapacity(lines.count)
        var cursor = 0
        for line in lines {
            let length = (line as NSString).length
            ranges.append(NSRange(location: cursor, length: length))
            cursor += length + 1
        }
        return ranges
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

    private static func makeMarksByLine(
        _ marks: [FolioCommentMark]
    ) -> [AnchorRange.Side: [Int: FolioCommentMark]] {
        var byLine: [AnchorRange.Side: [Int: FolioCommentMark]] = [:]
        for mark in marks {
            byLine[mark.side, default: [:]][mark.line] = mark
        }
        return byLine
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
