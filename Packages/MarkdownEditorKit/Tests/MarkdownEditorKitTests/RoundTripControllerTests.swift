import Foundation
import Testing
@testable import MarkdownEditorKit
#if canImport(AppKit) && os(macOS)
import AppKit
#endif

@Suite("Round-trip controller")
@MainActor
struct RoundTripControllerTests {
    @Test(arguments: CorpusFixtures.canonical + CorpusFixtures.canonicalizing)
    func unchangedDocumentReturnsOriginalBytes(_ sample: CorpusSample) {
        let controller = MarkdownEditorController(markdown: sample.source)
        #expect(controller.markdown() == sample.source)
    }

    @Test(arguments: CorpusFixtures.remarkupDrafts)
    func unchangedDraftWithLabelsReturnsOriginalBytes(_ sample: CorpusSample) {
        let controller = MarkdownEditorController(
            markdown: sample.source,
            inlineContentRules: Corpus.labelRules,
            inlineContentProvider: Corpus.labelProvider
        )
        #expect(controller.markdown() == sample.source)
    }

    @Test func setMarkdownResetsTheOriginal() {
        let controller = MarkdownEditorController(markdown: "* a")
        controller.setMarkdown("+ b\n+ c")
        #expect(controller.markdown() == "+ b\n+ c")
    }

    #if canImport(AppKit) && os(macOS)
    @Test(arguments: CorpusFixtures.canonicalizing)
    func undoingBackToTheLoadedStateReturnsOriginalBytes(_ sample: CorpusSample) throws {
        let harness = EditorHarness(markdown: sample.source)
        #expect(harness.controller.markdown() == sample.source)
        harness.select(harness.storage.length)
        harness.type("Z")
        let edited = harness.controller.markdown()
        #expect(edited != sample.source)
        #expect(edited.contains("Z"))
        harness.undo()
        #expect(harness.string == MarkdownLoader().load(sample.source).string)
        #expect(harness.controller.markdown() == sample.source)
        let lastPush = try #require(harness.pushes.last)
        #expect(lastPush == sample.source)
    }

    @Test func redoAfterUndoReturnsTheEditedSerialization() {
        let source = "* star\n* list"
        let harness = EditorHarness(markdown: source)
        harness.select(harness.storage.length)
        harness.type("!")
        let edited = harness.controller.markdown()
        harness.undo()
        #expect(harness.controller.markdown() == source)
        harness.redo()
        #expect(harness.controller.markdown() == edited)
    }
    #endif
}
