import Foundation

public struct DocumentChange: Sendable {
    public enum Origin: Sendable, Equatable {
        case user
        case command
        case undo
        case load
    }

    public let editedRange: NSRange
    public let changeInLength: Int
    public let origin: Origin

    public init(editedRange: NSRange, changeInLength: Int, origin: Origin) {
        self.editedRange = editedRange
        self.changeInLength = changeInLength
        self.origin = origin
    }
}
