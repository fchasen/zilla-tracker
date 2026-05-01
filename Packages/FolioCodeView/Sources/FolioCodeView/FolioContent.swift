import Foundation
import SwiftUI
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

public struct FolioComposerSlot {
    public let line: Int
    public let side: AnchorRange.Side
    public let content: () -> AnyView

    public init(line: Int, side: AnchorRange.Side, content: @escaping () -> AnyView) {
        self.line = line
        self.side = side
        self.content = content
    }
}
