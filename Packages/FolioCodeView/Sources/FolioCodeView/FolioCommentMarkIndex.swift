import FolioModel

struct FolioCommentMarkIndex: Sendable, Equatable {
    static let empty = FolioCommentMarkIndex()

    private let byLine: [AnchorRange.Side: [Int: FolioCommentMark]]

    init(_ marks: [FolioCommentMark] = []) {
        var byLine: [AnchorRange.Side: [Int: FolioCommentMark]] = [:]
        for mark in marks {
            byLine[mark.side, default: [:]][mark.line] = mark
        }
        self.byLine = byLine
    }

    func mark(side: AnchorRange.Side, line: Int) -> FolioCommentMark? {
        byLine[side]?[line]
    }
}
