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

    @Test func sourceAndDisplayMatchOnPlainText() throws {
        // Plain text (no markup) — display always matches source.
        let c = try EditorController(initialText: "hello world")
        c.refreshNow()
        #expect(c.sourceStorage.string == "hello world")
        #expect(c.textStorage.string == "hello world")
    }

    @Test func setTextUpdatesBothStorages() throws {
        // Caret on the heading line keeps markdown visible — display matches
        // source for the active line.
        let c = try EditorController(initialText: "old")
        c.setText("# new heading")
        c.selection = NSRange(location: 0, length: 0)
        c.refreshNow()
        #expect(c.sourceStorage.string == "# new heading")
        #expect(c.textStorage.string == "# new heading")
        #expect(c.text == "# new heading")
    }

    @Test func displayEditMirrorsToSource() throws {
        let c = try EditorController(initialText: "hello")
        c.refreshNow()
        c.textStorage.replaceCharacters(in: NSRange(location: 5, length: 0), with: " world")
        #expect(c.sourceStorage.string == "hello world")
        #expect(c.text == "hello world")
    }

    @Test func applyEditUpdatesSource() throws {
        let c = try EditorController(initialText: "Hello\n")
        c.applyEdit(replacing: NSRange(location: 0, length: 0), with: "# ")
        c.selection = NSRange(location: 0, length: 0)
        c.refreshNow()
        #expect(c.sourceStorage.string == "# Hello\n")
        // Caret on the heading line — markdown stays visible.
        #expect(c.textStorage.string == "# Hello\n")
    }

    // MARK: - active-line focus

    @Test func headingMarkerElidesWhenCaretIsOffLine() throws {
        // Cursor on line 1 (the body) — line 0's heading marker collapses.
        let c = try EditorController(initialText: "# Heading\nbody")
        c.selection = NSRange(location: 12, length: 0)
        c.refreshNow()
        #expect(c.textStorage.string == "Heading\nbody")
    }

    @Test func activeLineKeepsMarkdownVisible() throws {
        // Cursor on line 0 — markdown for that line stays visible so the
        // user can edit the markup directly.
        let c = try EditorController(initialText: "# Heading\nbody")
        c.selection = NSRange(location: 0, length: 0)
        c.refreshNow()
        #expect(c.textStorage.string == "# Heading\nbody")
    }

    @Test func emphasisDelimitersElideOffActiveLine() throws {
        let c = try EditorController(initialText: "**bold**\nsecond")
        c.selection = NSRange(location: 9, length: 0)
        c.refreshNow()
        #expect(c.textStorage.string == "bold\nsecond")
    }

    @Test func inlineLinkSyntaxElidesOffActiveLine() throws {
        let c = try EditorController(initialText: "see [docs](https://example.com)\nbody")
        c.selection = NSRange(location: 32, length: 0)
        c.refreshNow()
        #expect(c.textStorage.string == "see docs\nbody")
    }

    @Test func listMarkerStaysVisible() throws {
        // Cursor on the body line — line 0's `- ` bullet stays in display
        // so the bullet glyph substitution can render.
        let c = try EditorController(initialText: "- foo\nbar")
        c.selection = NSRange(location: 6, length: 0)
        c.refreshNow()
        #expect(c.textStorage.string == "- foo\nbar")
    }

    @Test func selectionMoveAcrossLinesRebuildsDisplay() throws {
        let c = try EditorController(initialText: "# Heading\nbody")
        c.selection = NSRange(location: 0, length: 0)
        c.refreshNow()
        // Active line is line 0 — heading markdown visible.
        #expect(c.textStorage.string == "# Heading\nbody")
        c.selection = NSRange(location: 12, length: 0)
        // Active line is now the body line — the heading line elides.
        #expect(c.textStorage.string == "Heading\nbody")
    }

    // MARK: - checkbox + image substitutions

    @Test func uncheckedTaskShowsCheckboxAttachmentOffActiveLine() throws {
        // Caret off the task line so the bullet elides and the checkbox
        // substitution kicks in.
        let c = try EditorController(initialText: "- [ ] task\nbody")
        c.selection = NSRange(location: 12, length: 0)
        c.refreshNow()
        // Display starts with the `￼` placeholder (no bullet).
        #expect(c.textStorage.string == "\u{FFFC} task\nbody")
        let attrs = c.textStorage.attributes(at: 0, effectiveRange: nil)
        let attachment = try #require(attrs[.attachment] as? CheckboxAttachment)
        #expect(attachment.isChecked == false)
    }

    @Test func checkedTaskCheckboxIsChecked() throws {
        let c = try EditorController(initialText: "- [x] done\nbody")
        c.selection = NSRange(location: 12, length: 0)
        c.refreshNow()
        let attrs = c.textStorage.attributes(at: 0, effectiveRange: nil)
        let attachment = try #require(attrs[.attachment] as? CheckboxAttachment)
        #expect(attachment.isChecked == true)
    }

    @Test func taskLineHidesBulletAndShowsCheckbox() throws {
        let c = try EditorController(initialText: "- [ ] task\nbody")
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

    // MARK: - undo through source

    @Test func undoRevertsSourceEdit() throws {
        let c = try EditorController(initialText: "hello")
        c.applyEdit(replacing: NSRange(location: 5, length: 0), with: " world")
        #expect(c.text == "hello world")
        c.undoManager.undo()
        #expect(c.text == "hello")
    }

    @Test func redoReappliesSourceEdit() throws {
        let c = try EditorController(initialText: "hello")
        c.applyEdit(replacing: NSRange(location: 5, length: 0), with: " world")
        c.undoManager.undo()
        c.undoManager.redo()
        #expect(c.text == "hello world")
    }

    @Test func undoStackLayersMultipleEdits() throws {
        let c = try EditorController(initialText: "")
        c.applyEdit(replacing: NSRange(location: 0, length: 0), with: "a")
        c.applyEdit(replacing: NSRange(location: 1, length: 0), with: "b")
        c.applyEdit(replacing: NSRange(location: 2, length: 0), with: "c")
        #expect(c.text == "abc")
        c.undoManager.undo()
        #expect(c.text == "ab")
        c.undoManager.undo()
        #expect(c.text == "a")
        c.undoManager.undo()
        #expect(c.text == "")
    }

    @Test func taskToggleIsUndoable() throws {
        let c = try EditorController(initialText: "- [ ] task")
        c.toggleTask(atSourceLocation: 2)
        #expect(c.text == "- [x] task")
        c.undoManager.undo()
        #expect(c.text == "- [ ] task")
    }

    @Test func imageRangeIsSubstitutedToObjectReplacement() throws {
        let c = try EditorController(initialText: "see ![alt](https://example.com/x.png) here\nbody")
        c.selection = NSRange(location: 44, length: 0)
        c.refreshNow()
        #expect(c.textStorage.string == "see \u{FFFC} here\nbody")
    }

    @Test func imageObjectReplacementGetsChipAttachment() throws {
        let c = try EditorController(initialText: "![alt text](https://example.com/x.png)\nbody")
        c.selection = NSRange(location: 39, length: 0)
        c.refreshNow()
        let attrs = c.textStorage.attributes(at: 0, effectiveRange: nil)
        let attachment = try #require(attrs[.attachment] as? ChipTextAttachment)
        #expect(attachment.chipLabel == "alt text")
        #expect(attachment.chipSymbol == "photo")
    }

    @Test func emptyImageAltFallsBackToPlaceholderLabel() throws {
        let c = try EditorController(initialText: "![](https://example.com/x.png)\nbody")
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
        // Caret on a non-task fourth line so all three task lines elide.
        let source = "- [ ] one\n- [ ] two\n- [ ] three\nbody"
        let c = try EditorController(initialText: source)
        c.selection = NSRange(location: (source as NSString).length, length: 0)
        c.refreshNow()
        let count = c.textStorage.string.filter { $0 == "\u{FFFC}" }.count
        #expect(count == 3, "expected 3 checkboxes in: \(c.textStorage.string)")
    }

    @Test func emptySecondTaskLineGetsCheckboxSubstitution() throws {
        // Reproduces the "hit return → new task line missing checkbox" path:
        // ListContinuation produces "- [ ] " as the new line; we need that
        // trailing-space-only marker to still substitute its `[ ]`.
        let source = "- [ ] one\n- [ ] \nbody"
        let c = try EditorController(initialText: source)
        c.selection = NSRange(location: (source as NSString).length, length: 0)
        c.refreshNow()
        let count = c.textStorage.string.filter { $0 == "\u{FFFC}" }.count
        #expect(count == 2, "expected 2 checkboxes in: \(c.textStorage.string)")
    }

    @Test func threeTaskLinesActiveLastShowsTwoCheckboxes() throws {
        let source = "* [ ] gt\n* [ ] this\n* [ ] "
        let c = try EditorController(initialText: source)
        c.selection = NSRange(location: (source as NSString).length, length: 0)
        c.refreshNow()
        #expect(c.textStorage.string == "\u{FFFC} gt\n\u{FFFC} this\n* [ ] ")
        let firstAttrs = c.textStorage.attributes(at: 0, effectiveRange: nil)
        let firstAttachment = try #require(firstAttrs[.attachment] as? CheckboxAttachment)
        #expect(firstAttachment.isChecked == false)
        let secondCheckboxIndex = ("\u{FFFC} gt\n" as NSString).length
        let secondAttrs = c.textStorage.attributes(at: secondCheckboxIndex, effectiveRange: nil)
        let secondAttachment = try #require(secondAttrs[.attachment] as? CheckboxAttachment)
        #expect(secondAttachment.isChecked == false)
    }
}
