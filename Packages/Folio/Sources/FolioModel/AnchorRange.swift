import Foundation

public struct AnchorRange: Sendable, Hashable {
    public enum Side: Sendable, Hashable {
        case oldFile
        case newFile
    }

    public let line: Int
    public let length: Int
    public let side: Side

    public init(line: Int, length: Int, side: Side) {
        self.line = line
        self.length = max(1, length)
        self.side = side
    }
}
