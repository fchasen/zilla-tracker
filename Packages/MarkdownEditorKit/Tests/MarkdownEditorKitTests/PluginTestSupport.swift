import Foundation
import Testing
@testable import MarkdownEditorKit

@MainActor
struct HeadlessEditor {
    let controller: MarkdownEditorController

    init(markdown: String = "") {
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        controller = MarkdownEditorController(markdown: markdown, undoManager: undoManager)
        controller.setSelection(NSRange(location: controller.textStorage.length, length: 0))
    }

    var string: String { controller.textStorage.string }
    var selection: NSRange { controller.currentSelection }

    func select(_ location: Int) {
        controller.setSelection(NSRange(location: location, length: 0))
    }

    @discardableResult
    func type(_ text: String) -> Bool {
        let range = controller.currentSelection
        for plugin in controller.plugins {
            if plugin.props.handleTextInput?(controller, range, text) == true { return false }
        }
        let attributes = controller.typingAttributes(at: range.location)
        controller.textStorage.replaceCharacters(in: range, with: NSAttributedString(string: text, attributes: attributes))
        controller.setSelection(NSRange(location: range.location + (text as NSString).length, length: 0))
        controller.flushDocumentChanges()
        return true
    }

    func typeEach(_ text: String) {
        for character in text {
            type(String(character))
            settle()
        }
    }

    func backspace() {
        let caret = controller.currentSelection.location
        guard caret > 0 else { return }
        let range = NSRange(location: caret - 1, length: 1)
        for plugin in controller.plugins {
            if plugin.props.handleTextInput?(controller, range, "") == true { return }
        }
        controller.textStorage.replaceCharacters(in: range, with: "")
        controller.setSelection(NSRange(location: range.location, length: 0))
        controller.flushDocumentChanges()
    }

    func key(_ name: String) -> Bool {
        for plugin in controller.plugins {
            if plugin.props.handleKeyDown?(controller, name) == true { return true }
        }
        return false
    }

    func settle() {
        controller.flushDocumentChanges()
        controller.drainDeferredEdits()
    }

    func link(at index: Int) -> String? {
        controller.textStorage.markdownLink(at: index)
    }

    func linkRange(at index: Int) -> NSRange? {
        guard controller.textStorage.markdownLink(at: index) != nil else { return nil }
        var effective = NSRange()
        _ = controller.textStorage.attribute(
            .link,
            at: index,
            longestEffectiveRange: &effective,
            in: NSRange(location: 0, length: controller.textStorage.length)
        )
        return effective
    }
}

enum PluginFixtures {
    static let referenceRules: [AutoLinkRule] = [
        AutoLinkRule(
            id: "test.revision",
            pattern: #"(^|[^A-Za-z0-9_\/])((D)(\d+))(?=$|[\s.,;:!?\)])"#,
            linkCapture: 2,
            href: { match in match.capture(4).map { "https://phabricator.services.mozilla.com/D\($0)" } }
        ),
        AutoLinkRule(
            id: "test.bug-word",
            pattern: #"(^|[^A-Za-z0-9_\/])(([Bb]ug)\s+(\d+))(?=$|[\s.,;:!?\)])"#,
            linkCapture: 2,
            href: { match in match.capture(4).map { "https://bugzilla.mozilla.org/show_bug.cgi?id=\($0)" } }
        ),
    ]

    static func mentionPlugin(allowedInCode: Bool = false) -> CompletionPlugin {
        CompletionPlugin(triggers: [
            CompletionTrigger(id: "mention", prefix: "@", allowedInCode: allowedInCode),
            CompletionTrigger(id: "tag", prefix: "#"),
        ])
    }
}
