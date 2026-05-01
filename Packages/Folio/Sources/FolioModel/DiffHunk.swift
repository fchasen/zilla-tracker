import Foundation

public struct DiffHunk: Sendable, Hashable {
    public let oldStart: Int
    public let newStart: Int
    public let lines: [DiffLine]

    public init(oldStart: Int, newStart: Int, lines: [DiffLine]) {
        self.oldStart = oldStart
        self.newStart = newStart
        self.lines = lines
    }
}

public extension DiffHunk {
    func indexOfFirstLine(matching anchor: AnchorRange) -> Int? {
        switch anchor.side {
        case .newFile:
            return lines.firstIndex { $0.newNumber == anchor.line }
        case .oldFile:
            return lines.firstIndex { $0.oldNumber == anchor.line }
        }
    }

    func contains(_ anchor: AnchorRange) -> Bool {
        indexOfFirstLine(matching: anchor) != nil
    }
}
