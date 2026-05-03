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

    @Test func wysiwygModeElidesHeadingMarkerWhenCaretIsOffLine() throws {
        // Cursor on line 1 (the body) — line 0's heading marker collapses.
        let c = try EditorController(initialText: "# Heading\nbody")
        c.mode = .wysiwyg
        c.selection = NSRange(location: 12, length: 0)
        c.refreshNow()
        #expect(c.textStorage.string == "Heading\nbody")
    }

    @Test func wysiwygModeKeepsActiveLineMarkdownVisible() throws {
        // Cursor on line 0 — markdown for that line stays visible so the
        // user can edit the markup directly.
        let c = try EditorController(initialText: "# Heading\nbody")
        c.mode = .wysiwyg
        c.selection = NSRange(location: 0, length: 0)
        c.refreshNow()
        #expect(c.textStorage.string == "# Heading\nbody")
    }

    @Test func wysiwygModeElidesEmphasisDelimitersOffLine() throws {
        let c = try EditorController(initialText: "**bold**\nsecond")
        c.mode = .wysiwyg
        c.selection = NSRange(location: 9, length: 0)
        c.refreshNow()
        #expect(c.textStorage.string == "bold\nsecond")
    }

    @Test func wysiwygModeElidesInlineLinkSyntaxOffLine() throws {
        let c = try EditorController(initialText: "see [docs](https://example.com)\nbody")
        c.mode = .wysiwyg
        c.selection = NSRange(location: 32, length: 0)
        c.refreshNow()
        #expect(c.textStorage.string == "see docs\nbody")
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
        let c = try EditorController(initialText: "# Heading\nbody")
        c.mode = .wysiwyg
        c.selection = NSRange(location: 12, length: 0)
        c.refreshNow()
        #expect(c.textStorage.string == "Heading\nbody")
        c.mode = .source
        #expect(c.textStorage.string == "# Heading\nbody")
    }

    @Test func wysiwygSelectionMoveAcrossLinesRebuildsDisplay() throws {
        let c = try EditorController(initialText: "# Heading\nbody")
        c.mode = .wysiwyg
        c.selection = NSRange(location: 0, length: 0)
        c.refreshNow()
        // Active line is line 0 — heading markdown visible.
        #expect(c.textStorage.string == "# Heading\nbody")
        c.selection = NSRange(location: 12, length: 0)
        // Active line is now the body line — the heading line elides.
        #expect(c.textStorage.string == "Heading\nbody")
    }

    // MARK: - checkbox + image substitutions

    @Test func uncheckedTaskUsesCheckboxAttachmentInSourceMode() throws {
        let c = try EditorController(initialText: "- [ ] task")
        c.mode = .source
        c.refreshNow()
        // Display keeps the bullet visible (source mode shows markdown);
        // only the bracket substitutes to a `￼` with a CheckboxAttachment.
        #expect(c.textStorage.string == "- \u{FFFC} task")
        let attrs = c.textStorage.attributes(at: 2, effectiveRange: nil)
        let attachment = try #require(attrs[.attachment] as? CheckboxAttachment)
        #expect(attachment.isChecked == false)
    }

    @Test func checkedTaskCheckboxIsChecked() throws {
        let c = try EditorController(initialText: "- [x] done")
        c.mode = .source
        c.refreshNow()
        let attrs = c.textStorage.attributes(at: 2, effectiveRange: nil)
        let attachment = try #require(attrs[.attachment] as? CheckboxAttachment)
        #expect(attachment.isChecked == true)
    }

    @Test func wysiwygTaskLineHidesBulletAndShowsCheckbox() throws {
        // Off-active-line task line in wysiwyg mode: bullet `- ` elides,
        // bracket substitutes to checkbox attachment.
        let c = try EditorController(initialText: "- [ ] task\nbody")
        c.mode = .wysiwyg
        c.selection = NSRange(location: 12, length: 0)
        c.refreshNow()
        // Display is "￼ task\nbody" — no bullet, just the checkbox.
        #expect(c.textStorage.string == "\u{FFFC} task\nbody")
    }

    @Test func toggleTaskFlipsBracket() throws {
        let c = try EditorController(initialText: "- [ ] one\n- [x] two")
        c.toggleTask(atSourceLocation: 2)
        #expect(c.text == "- [x] one\n- [x] two")
        c.toggleTask(atSourceLocation: 12)
        #expect(c.text == "- [x] one\n- [ ] two")
    }

    @Test func taskToggleURLRoundTrips() throws {
        let url = try #require(EditorController.taskToggleURL(forSourceLocation: 42))
        #expect(EditorController.taskToggleSourceLocation(from: url) == 42)
    }

    @Test func imageRangeIsSubstitutedToObjectReplacement() throws {
        let c = try EditorController(initialText: "see ![alt](https://example.com/x.png) here\nbody")
        c.mode = .wysiwyg
        c.selection = NSRange(location: 44, length: 0)
        c.refreshNow()
        #expect(c.textStorage.string == "see \u{FFFC} here\nbody")
    }

    @Test func imageObjectReplacementGetsChipAttachment() throws {
        let c = try EditorController(initialText: "![alt text](https://example.com/x.png)\nbody")
        c.mode = .wysiwyg
        c.selection = NSRange(location: 39, length: 0)
        c.refreshNow()
        let attrs = c.textStorage.attributes(at: 0, effectiveRange: nil)
        let attachment = try #require(attrs[.attachment] as? ChipTextAttachment)
        #expect(attachment.chipLabel == "alt text")
        #expect(attachment.chipSymbol == "photo")
    }

    @Test func emptyImageAltFallsBackToPlaceholderLabel() throws {
        let c = try EditorController(initialText: "![](https://example.com/x.png)\nbody")
        c.mode = .wysiwyg
        c.selection = NSRange(location: 31, length: 0)
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

    @Test func multipleTasksAllGetCheckboxSubstitution() throws {
        let source = "- [ ] one\n- [ ] two\n- [ ] three"
        let c = try EditorController(initialText: source)
        c.mode = .source
        c.refreshNow()
        // One `￼` per task line.
        let count = c.textStorage.string.filter { $0 == "\u{FFFC}" }.count
        #expect(count == 3, "expected 3 checkboxes in: \(c.textStorage.string)")
    }

    @Test func emptySecondTaskLineGetsCheckboxSubstitution() throws {
        // Reproduces the "hit return → new task line missing checkbox" path:
        // ListContinuation produces "- [ ] " as the new line; we need that
        // trailing-space-only marker to still substitute its `[ ]`.
        let source = "- [ ] one\n- [ ] "
        let c = try EditorController(initialText: source)
        c.mode = .source
        c.refreshNow()
        let count = c.textStorage.string.filter { $0 == "\u{FFFC}" }.count
        #expect(count == 2, "expected 2 checkboxes in: \(c.textStorage.string)")
    }
}
