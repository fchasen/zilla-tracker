import Foundation

public struct FoldedDiff: Sendable, Hashable {
    public enum Section: Sendable, Hashable {
        case lines(start: Int, end: Int)
        case gap(start: Int, end: Int)

        public var startIndex: Int {
            switch self {
            case let .lines(start, _), let .gap(start, _): return start
            }
        }

        public var endIndex: Int {
            switch self {
            case let .lines(_, end), let .gap(_, end): return end
            }
        }

        public var count: Int { endIndex - startIndex + 1 }
    }

    public let sections: [Section]

    public init(sections: [Section]) {
        self.sections = sections
    }
}

public enum DiffFolder {
    public static func fold(_ hunk: DiffHunk, contextLines: Int = 3) -> FoldedDiff {
        let total = hunk.lines.count
        guard total > 0 else { return FoldedDiff(sections: []) }

        var changeIndices: [Int] = []
        for (i, line) in hunk.lines.enumerated() where line.kind == .addition || line.kind == .deletion {
            changeIndices.append(i)
        }

        if changeIndices.isEmpty {
            return FoldedDiff(sections: [.gap(start: 0, end: total - 1)])
        }

        var ranges: [Range<Int>] = changeIndices.map { i in
            max(0, i - contextLines)..<(min(total - 1, i + contextLines) + 1)
        }
        ranges.sort { $0.lowerBound < $1.lowerBound }
        var merged: [Range<Int>] = []
        for r in ranges {
            if let last = merged.last, r.lowerBound <= last.upperBound {
                merged[merged.count - 1] = last.lowerBound..<max(last.upperBound, r.upperBound)
            } else {
                merged.append(r)
            }
        }

        var sections: [FoldedDiff.Section] = []
        var cursor = 0
        for r in merged {
            if r.lowerBound > cursor {
                sections.append(.gap(start: cursor, end: r.lowerBound - 1))
            }
            sections.append(.lines(start: r.lowerBound, end: r.upperBound - 1))
            cursor = r.upperBound
        }
        if cursor < total {
            sections.append(.gap(start: cursor, end: total - 1))
        }
        return FoldedDiff(sections: sections)
    }
}
