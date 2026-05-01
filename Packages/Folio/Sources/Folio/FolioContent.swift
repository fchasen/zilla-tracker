import Foundation
import FolioModel

public enum FolioContent: Sendable {
    case diff(DiffHunk, anchor: AnchorRange?, mode: DiffViewMode)
    case code(String, startLine: Int)

    public static func code(_ text: String) -> FolioContent {
        .code(text, startLine: 1)
    }
}

public enum DiffViewMode: Sendable, Hashable {
    case unified
    case split
}

public enum ExpandDirection: Sendable, Hashable {
    case up
    case down
}
