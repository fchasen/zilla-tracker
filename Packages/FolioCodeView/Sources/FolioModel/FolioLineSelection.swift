import Foundation

public struct FolioLineSelection: Sendable, Hashable {
    public let startLine: Int
    public let endLine: Int
    public let side: AnchorRange.Side

    public init(startLine: Int, endLine: Int, side: AnchorRange.Side) {
        let lo = min(startLine, endLine)
        let hi = max(startLine, endLine)
        self.startLine = lo
        self.endLine = hi
        self.side = side
    }

    public func contains(_ line: Int) -> Bool {
        line >= startLine && line <= endLine
    }
}
