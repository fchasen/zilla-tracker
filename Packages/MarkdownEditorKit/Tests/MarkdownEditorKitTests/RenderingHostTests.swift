#if canImport(AppKit) && os(macOS)
import AppKit
import Foundation
import Testing
@testable import MarkdownEditorKit

@Suite("Rendering host (macOS)")
@MainActor
struct RenderingHostTests {
    private func fragment(_ harness: EditorHarness, at offset: Int) -> MarkdownLayoutFragment? {
        let storage = harness.controller.textContentStorage
        guard let location = storage.location(storage.documentRange.location, offsetBy: offset) else { return nil }
        harness.controller.textLayoutManager.ensureLayout(for: storage.documentRange)
        return harness.controller.textLayoutManager.textLayoutFragment(for: location) as? MarkdownLayoutFragment
    }

    private func click(_ harness: EditorHarness, at point: NSPoint) {
        let windowPoint = harness.textView.convert(point, to: nil)
        let event = NSEvent.mouseEvent(
            with: .leftMouseDown, location: windowPoint, modifierFlags: [], timestamp: 0,
            windowNumber: harness.window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        )!
        harness.textView.mouseDown(with: event)
    }

    @Test func listsStayOnTextKit2() {
        let harness = EditorHarness(markdown: "1. one\n\n   more\n2. two\n\n> - [x] quoted task")
        #expect(harness.isTextKit2)
    }

    @Test func clickingTheDrawnCheckboxTogglesTheTask() throws {
        let harness = EditorHarness(markdown: "- [ ] task\n- other")
        harness.spin()
        let fragment = try #require(fragment(harness, at: 0))
        let box = try #require(fragment.markerRect)
        let origin = harness.textView.textContainerOrigin
        let center = NSPoint(
            x: origin.x + fragment.layoutFragmentFrame.minX + box.midX,
            y: origin.y + fragment.layoutFragmentFrame.minY + box.midY
        )
        click(harness, at: center)
        #expect(harness.controller.markdown() == "- [x] task\n- other")
        #expect(self.fragment(harness, at: 0)?.marker?.kind == .task(.checked))
        harness.undo()
        #expect(harness.controller.markdown() == "- [ ] task\n- other")
    }

    @Test func gutterHitTestCoversOnlyTheCheckbox() throws {
        let harness = EditorHarness(markdown: "- [ ] task")
        harness.spin()
        let rect = try #require(harness.controller.rect(forCharacterAt: 0))
        #expect(harness.textView.taskGutterIndex(at: NSPoint(x: rect.minX - 10, y: rect.midY), charIndex: 0) == 0)
        #expect(harness.textView.taskGutterIndex(at: NSPoint(x: rect.minX + 5, y: rect.midY), charIndex: 0) == nil)
    }

    @Test func nativeReturnNumbersTheNewItem() {
        let harness = EditorHarness(markdown: "1. one\n2. two")
        harness.select(3)
        harness.insertNewline()
        harness.type("new")
        harness.controller.flushDocumentChanges()
        #expect(harness.string == "one\nnew\ntwo")
        #expect(fragment(harness, at: 4)?.marker?.kind == .ordinal(2))
        #expect(fragment(harness, at: 8)?.marker?.kind == .ordinal(3))
        #expect(harness.controller.markdown() == "1. one\n2. new\n3. two")
    }

    @Test func viewDrawsMarkersInTheGutter() throws {
        let harness = EditorHarness(markdown: "- [x] done\n\nplain")
        harness.spin()
        let view = harness.textView
        let fragment = try #require(fragment(harness, at: 0))
        let box = try #require(fragment.markerRect)
        let origin = view.textContainerOrigin
        let target = NSRect(
            x: origin.x + fragment.layoutFragmentFrame.minX + box.minX,
            y: origin.y + fragment.layoutFragmentFrame.minY + box.minY,
            width: box.width,
            height: box.height
        )
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        var tinted = 0
        let scale = CGFloat(bitmap.pixelsWide) / view.bounds.width
        for y in Int(target.minY * scale)..<Int(target.maxY * scale) {
            for x in Int(target.minX * scale)..<Int(target.maxX * scale) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                if abs(color.redComponent - color.blueComponent) > 0.2 || color.brightnessComponent < 0.6 { tinted += 1 }
            }
        }
        #expect(tinted > 20)
    }

    @Test func horizontalRuleSpansTheLineAndIsDrawn() throws {
        let harness = EditorHarness(markdown: "above\n\n---\n\nbelow")
        harness.spin()
        let view = harness.textView
        let frame = try #require(fragment(harness, at: 6)).layoutFragmentFrame
        #expect(frame.width > 400)
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let scale = CGFloat(bitmap.pixelsWide) / view.bounds.width
        let origin = view.textContainerOrigin
        var widest = 0
        for y in Int((origin.y + frame.minY) * scale)..<Int((origin.y + frame.maxY) * scale) {
            var dark = 0
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                if color.brightnessComponent < 0.9 { dark += 1 }
            }
            widest = max(widest, dark)
        }
        #expect(CGFloat(widest) > frame.width * scale * 0.9)
    }

    @Test func blockAtomsTakeTheirMeasuredSize() throws {
        let harness = EditorHarness(markdown: "| a | b |\n|---|---|\n| 1 | 2 |\n\n<div>hi</div>")
        harness.spin()
        let table = try #require(fragment(harness, at: 0)).layoutFragmentFrame
        let html = try #require(fragment(harness, at: 2)).layoutFragmentFrame
        #expect(table.width > 40)
        #expect(table.height > 40)
        #expect(html.width > 400)
        #expect(html.height > 20)
    }
}
#endif
