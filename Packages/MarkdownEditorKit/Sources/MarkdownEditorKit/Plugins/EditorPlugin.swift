import Foundation
#if canImport(AppKit) && os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

public protocol EditorPlugin: AnyObject {
    var key: AnyPluginKey { get }
    var props: PluginProps { get }
    func documentDidChange(_ change: DocumentChange, controller: MarkdownEditorController)
}

public extension EditorPlugin {
    var props: PluginProps { PluginProps() }
    func documentDidChange(_ change: DocumentChange, controller: MarkdownEditorController) {}
}

public struct PluginProps {
    public var handleClick: ((MarkdownEditorController, Int) -> Bool)?
    public var handleLongPress: ((MarkdownEditorController, Int) -> Bool)?
    public var handlePaste: ((MarkdownEditorController, PasteEvent) -> Bool)?
    public var handleKeyDown: ((MarkdownEditorController, String) -> Bool)?
    public var handleTextInput: ((MarkdownEditorController, NSRange, String) -> Bool)?

    public init(
        handleClick: ((MarkdownEditorController, Int) -> Bool)? = nil,
        handleLongPress: ((MarkdownEditorController, Int) -> Bool)? = nil,
        handlePaste: ((MarkdownEditorController, PasteEvent) -> Bool)? = nil,
        handleKeyDown: ((MarkdownEditorController, String) -> Bool)? = nil,
        handleTextInput: ((MarkdownEditorController, NSRange, String) -> Bool)? = nil
    ) {
        self.handleClick = handleClick
        self.handleLongPress = handleLongPress
        self.handlePaste = handlePaste
        self.handleKeyDown = handleKeyDown
        self.handleTextInput = handleTextInput
    }
}

public struct AnyPluginKey: Hashable, Sendable {
    public let name: String
    public init(name: String) { self.name = name }
}

public struct PluginKey<State> {
    public let any: AnyPluginKey
    public init(name: String) { self.any = AnyPluginKey(name: name) }
}

public enum PluginKeyName {
    public static let escape = "Escape"
    public static let enter = "Enter"
    public static let tab = "Tab"
    public static let arrowUp = "ArrowUp"
    public static let arrowDown = "ArrowDown"
    public static let arrowLeft = "ArrowLeft"
    public static let arrowRight = "ArrowRight"
}
