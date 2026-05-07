import Foundation

public struct SplitRow: Sendable, Hashable {
    public let left: DiffLine?
    public let right: DiffLine?
    public let leftIndex: Int?
    public let rightIndex: Int?
    public let intralineDiff: IntralineDiff.Result?

    public init(
        left: DiffLine?,
        right: DiffLine?,
        leftIndex: Int? = nil,
        rightIndex: Int? = nil,
        intralineDiff: IntralineDiff.Result? = nil
    ) {
        self.left = left
        self.right = right
        self.leftIndex = leftIndex
        self.rightIndex = rightIndex
        self.intralineDiff = intralineDiff
    }
}

public enum SplitRowBuilder {
    public static func build(_ lines: [DiffLine]) -> [SplitRow] {
        build(lines[...]) { old, new in IntralineDiff.compute(old: old, new: new) }
    }

    public static func build(_ lines: ArraySlice<DiffLine>) -> [SplitRow] {
        build(lines) { old, new in IntralineDiff.compute(old: old, new: new) }
    }

    public static func build(
        _ lines: [DiffLine],
        intralineDiffProvider: (String, String) -> IntralineDiff.Result?
    ) -> [SplitRow] {
        build(lines[...], intralineDiffProvider: intralineDiffProvider)
    }

    public static func build(
        _ lines: ArraySlice<DiffLine>,
        intralineDiffProvider: (String, String) -> IntralineDiff.Result?
    ) -> [SplitRow] {
        var rows: [SplitRow] = []
        var pendingDeletions: [(idx: Int, line: DiffLine)] = []
        var pendingAdditions: [(idx: Int, line: DiffLine)] = []

        func flushPending() {
            let pairs = max(pendingDeletions.count, pendingAdditions.count)
            for i in 0..<pairs {
                let l = i < pendingDeletions.count ? pendingDeletions[i] : nil
                let r = i < pendingAdditions.count ? pendingAdditions[i] : nil
                let diff: IntralineDiff.Result? = (l != nil && r != nil)
                    ? intralineDiffProvider(l!.line.text, r!.line.text)
                    : nil
                rows.append(SplitRow(
                    left: l?.line,
                    right: r?.line,
                    leftIndex: l?.idx,
                    rightIndex: r?.idx,
                    intralineDiff: diff
                ))
            }
            pendingDeletions.removeAll(keepingCapacity: true)
            pendingAdditions.removeAll(keepingCapacity: true)
        }

        for i in lines.indices {
            let line = lines[i]
            switch line.kind {
            case .deletion:
                pendingDeletions.append((i, line))
            case .addition:
                pendingAdditions.append((i, line))
            case .context:
                flushPending()
                rows.append(SplitRow(left: line, right: line, leftIndex: i, rightIndex: i))
            case .noNewline:
                flushPending()
                rows.append(SplitRow(left: line, right: line, leftIndex: i, rightIndex: i))
            }
        }
        flushPending()
        return rows
    }
}
