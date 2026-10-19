import Foundation

public struct PasteEvent {

    public enum Source: Sendable, Equatable {
        case paste
        case dictation
    }

    public var text: String?
    public var html: String?
    public var plainText: Bool
    public var source: Source
    public var selection: NSRange
    public var inCode: Bool

    public init(
        text: String?,
        html: String? = nil,
        plainText: Bool = false,
        source: Source = .paste,
        selection: NSRange,
        inCode: Bool = false
    ) {
        self.text = text
        self.html = html
        self.plainText = plainText
        self.source = source
        self.selection = selection
        self.inCode = inCode
    }
}
