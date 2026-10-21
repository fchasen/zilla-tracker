import Foundation
import Testing
@testable import MarkdownEditorKit

@Suite("Auto-link plugin")
@MainActor
struct AutoLinkPluginTests {
    private func makeEditor(_ markdown: String = "", rules: [AutoLinkRule] = [.url, .email]) -> HeadlessEditor {
        let editor = HeadlessEditor(markdown: markdown)
        editor.controller.register(plugin: AutoLinkPlugin(rules: rules))
        return editor
    }

    @Test func keyNameMatchesKey() {
        #expect(AutoLinkPlugin(rules: []).key.name == AutoLinkPlugin.keyName)
    }

    @Test func wordInProgressIsNotLinked() {
        let editor = makeEditor()
        editor.type("see https://example.com")
        editor.settle()
        #expect(editor.link(at: 6) == nil)
    }

    @Test func trailingSpaceLinksPreviousWord() {
        let editor = makeEditor()
        editor.type("see https://example.com")
        editor.settle()
        editor.type(" ")
        editor.settle()
        #expect(editor.link(at: 6) == "https://example.com")
        #expect(editor.linkRange(at: 6) == NSRange(location: 4, length: 19))
        #expect(editor.link(at: 23) == nil)
        #expect(editor.controller.markdown() == "see https://example.com ")
    }

    @Test func editBeforePendingBoundaryStillLinks() {
        let editor = makeEditor()
        editor.type("see https://example.com")
        editor.settle()
        editor.type(" ")
        editor.select(0)
        editor.type("an insertion longer than the link ")
        editor.settle()
        #expect(editor.link(at: 40) == "https://example.com")
        #expect(editor.linkRange(at: 40) == NSRange(location: 38, length: 19))
    }

    @Test func trailingPunctuationStaysOutsideLink() {
        let editor = makeEditor()
        editor.type("go to https://example.com/a.")
        editor.settle()
        editor.type(" ")
        editor.settle()
        #expect(editor.linkRange(at: 7) == NSRange(location: 6, length: 21))
    }

    @Test func typingCharacterByCharacterLinksOnlyAtBoundary() {
        let editor = makeEditor(rules: PluginFixtures.referenceRules)
        editor.typeEach("D12")
        #expect(editor.link(at: 0) == nil)
        editor.typeEach("3 ")
        #expect(editor.link(at: 0) == "https://phabricator.services.mozilla.com/D123")
        #expect(editor.linkRange(at: 0) == NSRange(location: 0, length: 4))
    }

    @Test func captureRulesLinkOnlyTheLinkCapture() {
        let editor = makeEditor(rules: PluginFixtures.referenceRules)
        editor.typeEach("see bug 42, ok")
        #expect(editor.link(at: 3) == nil)
        #expect(editor.link(at: 4) == "https://bugzilla.mozilla.org/show_bug.cgi?id=42")
        #expect(editor.linkRange(at: 4) == NSRange(location: 4, length: 6))
        #expect(editor.controller.markdown() == "see [bug 42](https://bugzilla.mozilla.org/show_bug.cgi?id=42), ok")
    }

    @Test func leadingWordCharacterBlocksMatch() {
        let editor = makeEditor()
        editor.type("xhttps://example.com")
        editor.settle()
        editor.type(" ")
        editor.settle()
        #expect(editor.link(at: 3) == nil)
    }

    @Test func emailLinksWithMailto() {
        let editor = makeEditor()
        editor.type("mail a@example.org")
        editor.settle()
        editor.type(" ")
        editor.settle()
        #expect(editor.link(at: 6) == "mailto:a@example.org")
    }

    @Test func codeBlockIsSkipped() {
        let editor = makeEditor("```\nx\n```")
        editor.select(1)
        editor.type(" https://example.com ")
        editor.settle()
        #expect(editor.link(at: 5) == nil)
    }

    @Test func inlineCodeIsSkipped() {
        let editor = makeEditor("`https://example.com` and")
        editor.select(editor.controller.textStorage.length)
        editor.type(" ")
        editor.settle()
        #expect(editor.link(at: 3) == nil)
    }

    @Test func existingLinkIsLeftAlone() {
        let editor = makeEditor("[https://example.com](https://other.example)")
        editor.select(editor.controller.textStorage.length)
        editor.type(" ")
        editor.settle()
        #expect(editor.link(at: 3) == "https://other.example")
        #expect(editor.linkRange(at: 3) == NSRange(location: 0, length: 19))
    }

    @Test func unlinkedTextIsNotRelinkedByDistantEdits() {
        let editor = makeEditor("https://example.com and")
        #expect(editor.link(at: 3) != nil)
        editor.controller.setLink(nil, in: NSRange(location: 0, length: 19))
        editor.settle()
        #expect(editor.link(at: 3) == nil)
        editor.select(editor.controller.textStorage.length)
        editor.type(" more")
        editor.settle()
        #expect(editor.link(at: 3) == nil)
    }

    @Test func commandInsertLinksWithoutBoundary() {
        let editor = makeEditor(rules: PluginFixtures.referenceRules)
        editor.controller.replaceText(in: NSRange(location: 0, length: 0), with: "see D45")
        editor.settle()
        #expect(editor.link(at: 4) == "https://phabricator.services.mozilla.com/D45")
    }

    @Test func autoLinkIsItsOwnUndoStep() {
        let editor = makeEditor(rules: PluginFixtures.referenceRules)
        editor.controller.replaceText(in: NSRange(location: 0, length: 0), with: "see D45")
        editor.settle()
        #expect(editor.link(at: 4) != nil)
        editor.controller.undoManager.undo()
        editor.settle()
        #expect(editor.string == "see D45")
        #expect(editor.link(at: 4) == nil)
        editor.controller.undoManager.undo()
        editor.settle()
        #expect(editor.string == "")
    }

    @Test func multipleMatchesInOneEditShareOneStep() {
        let editor = makeEditor()
        editor.controller.replaceText(in: NSRange(location: 0, length: 0), with: "https://a.example and https://b.example")
        editor.settle()
        #expect(editor.link(at: 2) == "https://a.example")
        #expect(editor.link(at: 25) == "https://b.example")
        editor.controller.undoManager.undo()
        #expect(editor.link(at: 2) == nil)
        #expect(editor.link(at: 25) == nil)
        #expect(editor.string == "https://a.example and https://b.example")
    }

    @Test func notEditableDoesNothing() {
        let editor = makeEditor()
        editor.type("https://example.com")
        editor.controller.isEditable = false
        editor.type(" ")
        editor.settle()
        #expect(editor.link(at: 3) == nil)
    }
}

#if canImport(AppKit) && os(macOS)
import AppKit

@Suite("Auto-link plugin host (macOS)")
@MainActor
struct AutoLinkPluginHostTests {
    private func makeHarness(_ markdown: String = "") -> EditorHarness {
        let harness = EditorHarness(markdown: markdown)
        harness.controller.register(plugin: AutoLinkPlugin(rules: [.url] + PluginFixtures.referenceRules))
        harness.select(harness.string.utf16.count)
        return harness
    }

    @Test func spaceAfterURLLinksAndUndoRemovesOnlyTheLink() {
        let harness = makeHarness()
        harness.type("see https://example.com")
        harness.settle()
        #expect(harness.storage.markdownLink(at: 6) == nil)
        harness.type(" ")
        harness.settle()
        #expect(harness.storage.markdownLink(at: 6) == "https://example.com")
        #expect(harness.textView.typingAttributes[.link] == nil)
        harness.undo()
        #expect(harness.storage.markdownLink(at: 6) == nil)
        #expect(harness.string == "see https://example.com ")
    }

    @Test func returnAfterReferenceLinksIt() {
        let harness = makeHarness()
        harness.typeEach("fixed in D77")
        #expect(harness.storage.markdownLink(at: 9) == nil)
        harness.insertNewline()
        harness.settle()
        #expect(harness.storage.markdownLink(at: 9) == "https://phabricator.services.mozilla.com/D77")
        #expect(harness.markdown == "fixed in [D77](https://phabricator.services.mozilla.com/D77)")
    }

    @Test func typingInsideMarkedTextDoesNotLink() {
        let harness = makeHarness("D12")
        harness.setMarkedText(" ")
        harness.settle()
        #expect(harness.storage.markdownLink(at: 0) == nil)
        #expect(harness.textView.hasMarkedText())
    }
}
#endif
