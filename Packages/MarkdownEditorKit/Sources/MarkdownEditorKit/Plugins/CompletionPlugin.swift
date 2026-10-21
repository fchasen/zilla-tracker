import Foundation
#if canImport(AppKit) && os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

public struct CompletionTrigger: Equatable, Sendable {
    public let id: String
    public let prefix: Character
    public let allowedInCode: Bool

    public init(id: String, prefix: Character, allowedInCode: Bool = false) {
        self.id = id
        self.prefix = prefix
        self.allowedInCode = allowedInCode
    }
}

public struct CompletionContext: Equatable, Sendable {
    public let triggerID: String
    public let query: String
    public let range: NSRange
    public let caretRect: CGRect?

    public init(triggerID: String, query: String, range: NSRange, caretRect: CGRect?) {
        self.triggerID = triggerID
        self.query = query
        self.range = range
        self.caretRect = caretRect
    }
}

public struct CompletionSession: Equatable, Sendable {
    public var context: CompletionContext
    public var highlightedIndex: Int
    public var itemCount: Int

    public init(context: CompletionContext, highlightedIndex: Int = 0, itemCount: Int = 0) {
        self.context = context
        self.highlightedIndex = highlightedIndex
        self.itemCount = itemCount
    }
}

public final class CompletionPlugin: EditorPlugin {
    public static let keyName = "markdowneditorkit.completion"
    public static let stateKey = PluginKey<CompletionSession>(name: keyName)
    public let key = AnyPluginKey(name: keyName)

    public let triggers: [CompletionTrigger]
    public var onSessionChanged: ((CompletionSession?) -> Void)?
    public var onCommit: ((MarkdownEditorController, CompletionSession) -> Void)?
    private var isCommitting = false

    public init(triggers: [CompletionTrigger]) {
        self.triggers = triggers
    }

    public func attach(to controller: MarkdownEditorController) {
        guard !controller.plugins.contains(where: { $0 === self }) else { return }
        controller.register(plugin: self)
        controller.addOnSelectionChanged { [weak self, weak controller] selection in
            guard let self, let controller else { return }
            self.selectionDidChange(selection, controller: controller)
        }
    }

    public var props: PluginProps {
        PluginProps(
            handleKeyDown: { [weak self] controller, key in
                self?.handleKey(controller: controller, key: key) ?? false
            },
            handleTextInput: { [weak self] controller, range, text in
                self?.handleTextInput(controller: controller, range: range, text: text) ?? false
            }
        )
    }

    public func documentDidChange(_ change: DocumentChange, controller: MarkdownEditorController) {
        if change.origin == .load {
            cancel(controller: controller)
            return
        }
        refresh(controller: controller)
    }

    public func session(controller: MarkdownEditorController) -> CompletionSession? {
        currentSession(controller)
    }

    public func updateHighlight(_ index: Int, controller: MarkdownEditorController) {
        guard var session = currentSession(controller) else { return }
        let clamped = max(0, min(index, max(0, session.itemCount - 1)))
        guard clamped != session.highlightedIndex else { return }
        session.highlightedIndex = clamped
        store(session, controller: controller)
    }

    public func updateItemCount(_ count: Int, controller: MarkdownEditorController) {
        guard var session = currentSession(controller) else { return }
        session.itemCount = max(0, count)
        if session.highlightedIndex >= session.itemCount {
            session.highlightedIndex = max(0, session.itemCount - 1)
        }
        store(session, controller: controller)
    }

    public func commit(controller: MarkdownEditorController) {
        guard let session = currentSession(controller) else { return }
        isCommitting = true
        onCommit?(controller, session)
        isCommitting = false
        clear(controller: controller)
    }

    public func cancel(controller: MarkdownEditorController) {
        guard currentSession(controller) != nil else { return }
        clear(controller: controller)
    }

    public func refresh(controller: MarkdownEditorController) {
        guard !isCommitting, let session = currentSession(controller) else { return }
        deriveSession(from: session, controller: controller)
    }

    private func selectionDidChange(_ selection: NSRange, controller: MarkdownEditorController) {
        guard !isCommitting, !isComposing(controller), !controller.hasPendingDocumentChange,
              let session = currentSession(controller) else { return }
        let range = session.context.range
        if selection.location < range.location + 1 || NSMaxRange(selection) > NSMaxRange(range) {
            cancel(controller: controller)
        }
    }

    private func isComposing(_ controller: MarkdownEditorController) -> Bool {
        controller.hostHasMarkedText || controller.isSettingMarkedText
    }

    private func handleKey(controller: MarkdownEditorController, key: String) -> Bool {
        guard let session = currentSession(controller), !isComposing(controller) else { return false }
        switch key {
        case PluginKeyName.escape:
            cancel(controller: controller)
            return true
        case PluginKeyName.arrowDown:
            guard session.itemCount > 0 else { return false }
            updateHighlight(session.highlightedIndex + 1, controller: controller)
            return true
        case PluginKeyName.arrowUp:
            guard session.itemCount > 0 else { return false }
            updateHighlight(session.highlightedIndex - 1, controller: controller)
            return true
        case PluginKeyName.enter, PluginKeyName.tab:
            guard session.itemCount > 0 else {
                cancel(controller: controller)
                return false
            }
            commit(controller: controller)
            return true
        default:
            return false
        }
    }

    private func handleTextInput(
        controller: MarkdownEditorController,
        range: NSRange,
        text: String
    ) -> Bool {
        if controller.isApplyingCommand || isComposing(controller) { return false }
        if let existing = currentSession(controller) {
            if Self.isCommitInput(text) {
                guard existing.itemCount > 0 else {
                    clear(controller: controller)
                    return false
                }
                controller.deferEdit { [weak self, weak controller] in
                    guard let self, let controller, self.currentSession(controller)?.context.range.location == existing.context.range.location else { return }
                    self.commit(controller: controller)
                }
                return true
            }
            if text.isEmpty {
                shrinkOrCloseSession(existing, deleting: range, controller: controller)
            } else {
                extendOrCloseSession(existing, range: range, text: text, controller: controller)
            }
            return false
        }
        if text.count == 1,
           let ch = text.first,
           let trigger = triggers.first(where: { $0.prefix == ch }),
           shouldOpen(at: range.location, replacing: range, in: controller, trigger: trigger) {
            let context = CompletionContext(
                triggerID: trigger.id,
                query: "",
                range: NSRange(location: range.location, length: (text as NSString).length),
                caretRect: controller.caretRect()
            )
            store(CompletionSession(context: context), controller: controller)
        }
        return false
    }

    private static func isCommitInput(_ text: String) -> Bool {
        text == "\n" || text == "\r" || text == "\r\n" || text == "\t"
    }

    private func extendOrCloseSession(
        _ session: CompletionSession,
        range: NSRange,
        text: String,
        controller: MarkdownEditorController
    ) {
        let expectedEnd = NSMaxRange(session.context.range)
        guard range.location == expectedEnd, range.length == 0 else {
            clear(controller: controller)
            return
        }
        if text.contains(where: { $0.isWhitespace || $0.isNewline }) {
            clear(controller: controller)
            return
        }
        if text.contains(where: { ch in triggers.contains(where: { $0.prefix == ch }) }) {
            clear(controller: controller)
            return
        }
        var updated = session
        updated.context = CompletionContext(
            triggerID: session.context.triggerID,
            query: session.context.query + text,
            range: NSRange(
                location: session.context.range.location,
                length: session.context.range.length + (text as NSString).length
            ),
            caretRect: controller.caretRect()
        )
        store(updated, controller: controller)
    }

    private func shrinkOrCloseSession(
        _ session: CompletionSession,
        deleting range: NSRange,
        controller: MarkdownEditorController
    ) {
        let anchor = session.context.range.location
        let queryStart = anchor + 1
        guard range.location >= queryStart, NSMaxRange(range) <= NSMaxRange(session.context.range) else {
            clear(controller: controller)
            return
        }
        let query = session.context.query as NSString
        let local = NSRange(location: range.location - queryStart, length: range.length)
        guard NSMaxRange(local) <= query.length else {
            clear(controller: controller)
            return
        }
        var updated = session
        updated.context = CompletionContext(
            triggerID: session.context.triggerID,
            query: query.replacingCharacters(in: local, with: ""),
            range: NSRange(location: anchor, length: session.context.range.length - range.length),
            caretRect: controller.caretRect()
        )
        store(updated, controller: controller)
    }

    private func deriveSession(from session: CompletionSession, controller: MarkdownEditorController) {
        let storage = controller.textStorage
        let ns = storage.string as NSString
        let anchor = session.context.range.location
        guard anchor < ns.length,
              let triggerChar = ns.substring(with: NSRange(location: anchor, length: 1)).first,
              triggers.contains(where: { $0.prefix == triggerChar && $0.id == session.context.triggerID })
        else {
            clear(controller: controller)
            return
        }
        let expectedEnd = NSMaxRange(session.context.range)
        if expectedEnd <= ns.length,
           ns.substring(with: session.context.range) == String(triggerChar) + session.context.query {
            return
        }
        if let trimmed = trimSession(session, in: ns, controller: controller) {
            if trimmed != session { store(trimmed, controller: controller) }
        } else {
            clear(controller: controller)
        }
    }

    private func trimSession(
        _ session: CompletionSession,
        in ns: NSString,
        controller: MarkdownEditorController
    ) -> CompletionSession? {
        let anchor = session.context.range.location
        guard anchor < ns.length else { return nil }
        var end = anchor + 1
        while end < ns.length {
            let unit = ns.character(at: end)
            if unit == MarkdownParagraph.objectReplacement { break }
            if let scalar = Unicode.Scalar(unit), CharacterSet.whitespacesAndNewlines.contains(scalar) { break }
            end += 1
        }
        var updated = session
        updated.context = CompletionContext(
            triggerID: session.context.triggerID,
            query: ns.substring(with: NSRange(location: anchor + 1, length: end - anchor - 1)),
            range: NSRange(location: anchor, length: end - anchor),
            caretRect: session.context.caretRect
        )
        return updated
    }

    private func shouldOpen(
        at location: Int,
        replacing range: NSRange,
        in controller: MarkdownEditorController,
        trigger: CompletionTrigger
    ) -> Bool {
        let ns = controller.textStorage.string as NSString
        if location > 0, location <= ns.length {
            let previous = ns.substring(with: NSRange(location: location - 1, length: 1))
            if let ch = previous.first, !ch.isWhitespace, !ch.isNewline { return false }
        }
        if !trigger.allowedInCode {
            let info = controller.paragraphInfo(at: location)
            if info.block.isCode || info.block.isAtom { return false }
            if controller.isLocationInCode(location) { return false }
            if range.length == 0, location > 0, location < ns.length,
               controller.textStorage.markdownInlineIntent(at: location - 1).contains(.code),
               controller.hostTypingAttributes.markdownInlineIntent.contains(.code) {
                return false
            }
        }
        return true
    }

    private func currentSession(_ controller: MarkdownEditorController) -> CompletionSession? {
        controller.pluginState(for: Self.stateKey)
    }

    private func store(_ session: CompletionSession, controller: MarkdownEditorController) {
        controller.setPluginState(session, for: Self.stateKey)
        onSessionChanged?(session)
    }

    private func clear(controller: MarkdownEditorController) {
        controller.clearPluginState(for: Self.stateKey)
        onSessionChanged?(nil)
    }
}
