import Foundation

public struct SplitRow: Sendable, Hashable {
    public let left: DiffLine?
    public let right: DiffLine?
    public let intralineDiff: IntralineDiff.Result?

    public init(left: DiffLine?, right: DiffLine?, intralineDiff: IntralineDiff.Result? = nil) {
        self.left = left
        self.right = right
        self.intralineDiff = intralineDiff
    }
}

public enum SplitRowBuilder {
    public static func build(_ lines: [DiffLine]) -> [SplitRow] {
        var rows: [SplitRow] = []
        var pendingDeletions: [DiffLine] = []
        var pendingAdditions: [DiffLine] = []

        func flushPending() {
            let pairs = max(pendingDeletions.count, pendingAdditions.count)
            for i in 0..<pairs {
                let l = i < pendingDeletions.count ? pendingDeletions[i] : nil
                let r = i < pendingAdditions.count ? pendingAdditions[i] : nil
                let diff: IntralineDiff.Result? = (l != nil && r != nil)
                    ? IntralineDiff.compute(old: l!.text, new: r!.text)
                    : nil
                rows.append(SplitRow(left: l, right: r, intralineDiff: diff))
            }
            pendingDeletions.removeAll(keepingCapacity: true)
            pendingAdditions.removeAll(keepingCapacity: true)
        }

        for line in lines {
            switch line.kind {
            case .deletion:
                pendingDeletions.append(line)
            case .addition:
                pendingAdditions.append(line)
            case .context:
                flushPending()
                rows.append(SplitRow(left: line, right: line))
            case .noNewline:
                flushPending()
                rows.append(SplitRow(left: line, right: line))
            }
        }
        flushPending()
        return rows
    }
}
