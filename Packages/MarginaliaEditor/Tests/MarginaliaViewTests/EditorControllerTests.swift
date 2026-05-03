import Testing
import Foundation
#if canImport(AppKit) && os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif
import MarginaliaRendering
import MarginaliaSyntax
@testable import MarginaliaView

@Suite(.serialized) struct EditorControllerTests {

    @Test func initialTextSetsStorage() throws {
        let c = try EditorController(initialText: "hello")
        #expect(c.textStorage.string == "hello")
        #expect(c.text == "hello")
    }

    @Test func setTextReplacesContent() throws {
        let c = try EditorController(initialText: "hello")
        c.setText("# heading")
        #expect(c.text == "# heading")
    }

    @Test func initialRefreshComputesBlockRegions() throws {
        let c = try EditorController(initialText: "# heading\nbody\n")
        c.refreshNow()
        let kinds = c.blockRegions.map { $0.kind }
        #expect(kinds.contains(where: { if case .heading = $0 { return true } else { return false } }))
        #expect(kinds.contains(.paragraph))
    }

    @Test func highlightAttributesApplied() throws {
        let c = try EditorController(initialText: "**bold**")
        c.refreshNow()
        var effective: NSRange = NSRange(location: 0, length: 0)
        let attrs = c.textStorage.attributes(at: 2, effectiveRange: &effective)
        #expect(attrs[.font] != nil)
    }

    @Test func applyEditUpdatesStorage() throws {
        let c = try EditorController(initialText: "Hello\n")
        c.applyEdit(replacing: NSRange(location: 0, length: 0), with: "# ")
        c.refreshNow()
        #expect(c.text == "# Hello\n")
    }

    @Test func textKitStackIsConfigured() throws {
        let c = try EditorController()
        #expect(c.contentStorage.textStorage == c.textStorage)
        #expect(c.contentStorage.textLayoutManagers.contains(c.layoutManager))
        #expect(c.layoutManager.textContainer == c.textContainer)
    }

    // MARK: - source/display split

    @Test func sourceMatchesDisplayAfterInit() throws {
        let c = try EditorController(initialText: "hello world")
        c.mode = .source
        c.refreshNow()
        #expect(c.sourceStorage.string == "hello world")
        #expect(c.textStorage.string == "hello world")
    }

    @Test func setTextUpdatesBothStorages() throws {
        let c = try EditorController(initialText: "old")
        c.mode = .source
        c.setText("# new heading")
        #expect(c.sourceStorage.string == "# new heading")
        #expect(c.textStorage.string == "# new heading")
        #expect(c.text == "# new heading")
    }

    @Test func displayEditMirrorsToSource() throws {
        let c = try EditorController(initialText: "hello")
        c.mode = .source
        c.refreshNow()
        c.textStorage.replaceCharacters(in: NSRange(location: 5, length: 0), with: " world")
        #expect(c.sourceStorage.string == "hello world")
        #expect(c.text == "hello world")
    }

    @Test func applyEditUpdatesSource() throws {
        let c = try EditorController(initialText: "Hello\n")
        c.mode = .source
        c.applyEdit(replacing: NSRange(location: 0, length: 0), with: "# ")
        c.refreshNow()
        #expect(c.sourceStorage.string == "# Hello\n")
        #expect(c.textStorage.string == "# Hello\n")
    }

    // MARK: - mode

    @Test func sourceModeKeepsDisplayMatchingSource() throws {
        let c = try EditorController(initialText: "# Heading")
        c.mode = .source
        c.refreshNow()
        #expect(c.textStorage.string == "# Heading")
        #expect(c.hiddenRanges.isEmpty)
    }

    @Test func wysiwygModeElidesHeadingMarker() throws {
        let c = try EditorController(initialText: "# Heading")
        c.mode = .wysiwyg
        c.refreshNow()
        #expect(c.textStorage.string == "Heading")
        #expect(c.sourceStorage.string == "# Heading")
    }

    @Test func wysiwygModeElidesEmphasisDelimiters() throws {
        let c = try EditorController(initialText: "**bold**")
        c.mode = .wysiwyg
        c.refreshNow()
        #expect(c.textStorage.string == "bold")
    }

    @Test func wysiwygModeElidesInlineLinkSyntax() throws {
        let c = try EditorController(initialText: "see [docs](https://example.com)")
        c.mode = .wysiwyg
        c.refreshNow()
        #expect(c.textStorage.string == "see docs")
    }

    @Test func wysiwygModeKeepsListMarkerVisible() throws {
        let c = try EditorController(initialText: "- foo")
        c.mode = .wysiwyg
        c.refreshNow()
        // The dash itself stays in display so the bullet glyph substitution
        // has something to render.
        #expect(c.textStorage.string == "- foo")
    }

    @Test func switchingToSourceRestoresFullMarkdown() throws {
        let c = try EditorController(initialText: "# Heading")
        c.mode = .wysiwyg
        c.refreshNow()
        #expect(c.textStorage.string == "Heading")
        c.mode = .source
        #expect(c.textStorage.string == "# Heading")
    }

    // MARK: - checkbox + image substitutions

    @Test func uncheckedTaskShowsBallotBox() throws {
        let c = try EditorController(initialText: "- [ ] task")
        c.mode = .source
        c.refreshNow()
        #expect(c.textStorage.string == "- \u{2610} task")
    }

    @Test func checkedTaskShowsCheckedBallotBox() throws {
        let c = try EditorController(initialText: "- [x] done")
        c.mode = .source
        c.refreshNow()
        #expect(c.textStorage.string == "- \u{2611} done")
    }

    @Test func taskMarkerSubstitutionAppliesInBothModes() throws {
        let c = try EditorController(initialText: "- [ ] task")
        c.mode = .wysiwyg
        c.refreshNow()
        // List marker stays visible; only the checkbox glyph is substituted.
        #expect(c.textStorage.string == "- \u{2610} task")
    }

    @Test func imageRangeIsSubstitutedToObjectReplacement() throws {
        let c = try EditorController(initialText: "see ![alt](https://example.com/x.png) here")
        c.mode = .wysiwyg
        c.refreshNow()
        #expect(c.textStorage.string == "see \u{FFFC} here")
    }

    @Test func imageObjectReplacementGetsChipAttachment() throws {
        let c = try EditorController(initialText: "![alt text](https://example.com/x.png)")
        c.mode = .wysiwyg
        c.refreshNow()
        let attrs = c.textStorage.attributes(at: 0, effectiveRange: nil)
        let attachment = try #require(attrs[.attachment] as? ChipTextAttachment)
        #expect(attachment.chipLabel == "alt text")
        #expect(attachment.chipSymbol == "photo")
    }

    @Test func emptyImageAltFallsBackToPlaceholderLabel() throws {
        let c = try EditorController(initialText: "![](https://example.com/x.png)")
        c.mode = .wysiwyg
        c.refreshNow()
        let attrs = c.textStorage.attributes(at: 0, effectiveRange: nil)
        let attachment = try #require(attrs[.attachment] as? ChipTextAttachment)
        #expect(attachment.chipLabel == "image")
    }

    @Test func dialectSwitchTriggersRefresh() throws {
        let c = try EditorController(initialText: "//italic//")
        c.dialect = .remarkup
        c.refreshNow()
        #expect(c.dialect == .remarkup)
    }

    @Test func emptyTextProducesEmptyState() throws {
        let c = try EditorController(initialText: "")
        c.refreshNow()
        #expect(c.blockRegions == [])
        #expect(c.markupRanges == [])
        #expect(c.hiddenRanges == [])
    }

    // MARK: - applyEdit(EditResult)

    @Test func applyEditUpdatesTextAndSelection() throws {
        let c = try EditorController(initialText: "hello")
        let result = EditResult(text: "hello world", selection: NSRange(location: 6, length: 5))
        c.applyEdit(result)
        #expect(c.text == "hello world")
        #expect(c.selection == NSRange(location: 6, length: 5))
    }

    @Test func applyEditClampsSelectionPastNewTextEnd() throws {
        let c = try EditorController(initialText: "")
        let result = EditResult(
            text: "1. ",
            selection: NSRange(location: 159, length: 28)
        )
        c.applyEdit(result)
        #expect(c.text == "1. ")
        #expect(c.selection.location == 3)
        #expect(c.selection.length == 0)
    }

    @Test func clampedRangeShrinksOutOfBoundsRange() throws {
        let c = try EditorController(initialText: "hello")
        let clamped = c.clampedRange(NSRange(location: 159, length: 28))
        #expect(clamped == NSRange(location: 5, length: 0))
    }

    @Test func inlineRegionsExposeImageMetadata() throws {
        let source = "see ![alt text](https://example.com/x.png) inline"
        let c = try EditorController(initialText: source)
        c.refreshNow()
        let images = c.inlineRegions.compactMap { region -> (String, String)? in
            if case let .image(destination, alt) = region.kind { return (destination, alt) }
            return nil
        }
        #expect(images.count == 1)
        #expect(images.first?.0 == "https://example.com/x.png")
        #expect(images.first?.1 == "alt text")
    }

    @Test func inlineRegionsExposeInlineLinkMetadata() throws {
        let source = "see [docs](https://example.com) here"
        let c = try EditorController(initialText: source)
        c.refreshNow()
        let links = c.inlineRegions.compactMap { region -> (String, String)? in
            if case let .inlineLink(destination, label) = region.kind { return (destination, label) }
            return nil
        }
        #expect(links.count == 1)
        #expect(links.first?.0 == "https://example.com")
        #expect(links.first?.1 == "docs")
    }
}
