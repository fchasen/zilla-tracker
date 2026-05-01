import Foundation

public struct DiffLine: Sendable, Hashable {
    public enum Kind: Sendable, Hashable {
        case context
        case addition
        case deletion
        case noNewline
    }

    public let kind: Kind
    public let oldNumber: Int?
    public let newNumber: Int?
    public let text: String

    public init(kind: Kind, oldNumber: Int?, newNumber: Int?, text: String) {
        self.kind = kind
        self.oldNumber = oldNumber
        self.newNumber = newNumber
        self.text = text
    }
}
