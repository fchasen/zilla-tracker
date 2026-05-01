import Foundation
import FolioModel

public struct FolioCommentMark: Sendable, Hashable, Identifiable {
    public let id: String
    public let side: AnchorRange.Side
    public let line: Int
    public let count: Int

    public init(id: String, side: AnchorRange.Side, line: Int, count: Int = 1) {
        self.id = id
        self.side = side
        self.line = line
        self.count = max(1, count)
    }
}
