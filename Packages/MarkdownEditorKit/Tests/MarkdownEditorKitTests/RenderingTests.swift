import CoreGraphics
import Foundation
import Testing
#if canImport(AppKit) && os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif
@testable import MarkdownEditorKit

@MainActor
private struct Rendered {
    let controller: MarkdownEditorController

    init(_ markdown: String, width: CGFloat = 480) {
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        controller = MarkdownEditorController(markdown: markdown, undoManager: undoManager)
        controller.textContainer.size = CGSize(width: width, height: .greatestFiniteMagnitude)
    }

    var paragraphStarts: [Int] {
        controller.textStorage.markdownParagraphRanges().filter { $0.length > 0 }.map(\.location)
    }

    func fragments() -> [Int: NSTextLayoutFragment] {
        let storage = controller.textContentStorage
        var result: [Int: NSTextLayoutFragment] = [:]
        controller.textLayoutManager.enumerateTextLayoutFragments(
            from: storage.documentRange.location,
            options: [.ensuresLayout]
        ) { fragment in
            if let start = fragment.textElement?.elementRange?.location {
                result[storage.offset(from: storage.documentRange.location, to: start)] = fragment
            }
            return true
        }
        return result
    }

    func fragment(paragraph index: Int) -> NSTextLayoutFragment? {
        fragments()[paragraphStarts[index]]
    }

    func marker(paragraph index: Int) -> ListMarker.Kind? {
        (fragment(paragraph: index) as? MarkdownLayoutFragment)?.marker?.kind
    }

    func contentX(paragraph index: Int) -> CGFloat? {
        guard let fragment = fragment(paragraph: index) as? MarkdownLayoutFragment else {
            return fragment(paragraph: index)?.layoutFragmentFrame.minX
        }
        return fragment.layoutFragmentFrame.minX + fragment.contentStartX
    }
}

private func inkPixels(of fragment: MarkdownLayoutFragment, in band: CGRect) -> Int {
    let frame = fragment.layoutFragmentFrame
    let width = Int(ceil(frame.maxX + 20))
    let height = Int(ceil(frame.height + 4))
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return 0 }
    context.translateBy(x: 0, y: CGFloat(height))
    context.scaleBy(x: 1, y: -1)
    fragment.draw(at: CGPoint(x: frame.minX, y: 0), in: context)
    guard let data = context.data else { return 0 }
    let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
    var count = 0
    let minX = max(0, Int(band.minX)), maxX = min(width, Int(band.maxX))
    for row in 0..<height {
        for column in minX..<maxX where pixels[(row * width + column) * 4 + 3] > 40 {
            count += 1
        }
    }
    return count
}

@MainActor
@Suite("Rendering")
struct RenderingTests {
    @Test func listElementsCarryNoNativeTextLists() {
        let editor = Rendered("- one\n- two")
        let storage = editor.controller.textContentStorage
        var elements: [NSTextParagraph] = []
        storage.enumerateTextElements(from: storage.documentRange.location) { element in
            if let paragraph = element as? NSTextParagraph { elements.append(paragraph) }
            return true
        }
        #expect(elements.count == 2)
        for element in elements {
            let style = element.attributedString.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
            #expect(style?.textLists.isEmpty == true)
            #expect(!element.attributedString.string.contains("\t"))
        }
        #expect(StorageReader.textLists(in: editor.controller.textStorage, at: 0).count == 1)
    }

    @Test func bulletItemsGetBulletMarkers() {
        let editor = Rendered("- one\n  - nested\n- two")
        #expect(editor.marker(paragraph: 0) == .bullet("•"))
        #expect(editor.marker(paragraph: 1) == .bullet("◦"))
        #expect(editor.marker(paragraph: 2) == .bullet("•"))
    }

    @Test func orderedItemsNumberAcrossContinuationsAndSublists() {
        let editor = Rendered("7. seven\n\n   more seven\n   - nested\n8. eight\n9. nine")
        #expect(editor.marker(paragraph: 0) == .ordinal(7))
        #expect(editor.marker(paragraph: 1) == nil)
        #expect(editor.marker(paragraph: 2) == .bullet("◦"))
        #expect(editor.marker(paragraph: 3) == .ordinal(8))
        #expect(editor.marker(paragraph: 4) == .ordinal(9))
    }

    @Test func continuationAlignsWithItemContent() throws {
        let editor = Rendered("1. first\n\n   continued\n2. second")
        let item = try #require(editor.contentX(paragraph: 0))
        let continuation = try #require(editor.contentX(paragraph: 1))
        let second = try #require(editor.contentX(paragraph: 2))
        #expect(abs(item - continuation) < 0.5)
        #expect(abs(item - second) < 0.5)
        #expect(item >= Restyler.listIndent)
    }

    @Test func listInsideQuoteIsIndentedPastTheQuote() throws {
        let editor = Rendered("- plain\n\n> - quoted")
        let plain = try #require(editor.contentX(paragraph: 0))
        let quoted = try #require(editor.contentX(paragraph: 1))
        #expect(abs((quoted - plain) - Restyler.quoteIndent) < 0.5)
        let fragment = try #require(editor.fragment(paragraph: 1) as? MarkdownLayoutFragment)
        #expect(fragment.quoteBars.count == 1)
        #expect(fragment.marker?.kind == .bullet("•"))
    }

    @Test func taskItemsDrawCheckboxes() throws {
        let editor = Rendered("- [ ] open\n- [x] done\n- plain")
        #expect(editor.marker(paragraph: 0) == .task(.unchecked))
        #expect(editor.marker(paragraph: 1) == .task(.checked))
        #expect(editor.marker(paragraph: 2) == .bullet("•"))
        let fragment = try #require(editor.fragment(paragraph: 1) as? MarkdownLayoutFragment)
        let box = try #require(fragment.markerRect)
        let contentX = fragment.contentStartX
        #expect(box.maxX <= contentX)
        #expect(box.minX >= contentX - MarkdownTaskGutter.width)
    }

    @Test func togglingTaskRefreshesItsMarker() {
        let editor = Rendered("- [ ] open")
        #expect(editor.marker(paragraph: 0) == .task(.unchecked))
        #expect(editor.controller.toggleTask(at: 0))
        #expect(editor.marker(paragraph: 0) == .task(.checked))
    }

    @Test func insertingAnItemRenumbersLaterItems() {
        let editor = Rendered("1. a\n2. b\n3. c")
        #expect(editor.marker(paragraph: 2) == .ordinal(3))
        _ = editor.fragments()
        let storage = editor.controller.textStorage
        let attributes = storage.attributes(at: 0, effectiveRange: nil)
        #expect(editor.controller.replace(
            NSRange(location: 1, length: 0),
            with: NSAttributedString(string: "\nnew", attributes: attributes),
            actionName: "Insert",
            selection: nil
        ))
        #expect(storage.string == "a\nnew\nb\nc")
        let numbers = editor.paragraphStarts.indices.compactMap { editor.marker(paragraph: $0) }
        #expect(numbers == [.ordinal(1), .ordinal(2), .ordinal(3), .ordinal(4)])
    }

    @Test func markersAndBarsDrawInk() throws {
        let editor = Rendered("- [x] done\n- bullet\n\n> quote")
        let task = try #require(editor.fragment(paragraph: 0) as? MarkdownLayoutFragment)
        let bullet = try #require(editor.fragment(paragraph: 1) as? MarkdownLayoutFragment)
        let quote = try #require(editor.fragment(paragraph: 2) as? MarkdownLayoutFragment)
        #expect(inkPixels(of: task, in: CGRect(x: 0, y: 0, width: Restyler.listIndent, height: 100)) > 40)
        #expect(inkPixels(of: bullet, in: CGRect(x: 0, y: 0, width: Restyler.listIndent, height: 100)) > 4)
        #expect(inkPixels(of: quote, in: CGRect(x: 0, y: 0, width: 6, height: 100)) > 10)
    }

    @Test func themeChangeRefreshesDecorations() throws {
        let editor = Rendered("> - [ ] quoted")
        _ = editor.fragments()
        var theme = MarkdownEditorTheme.default
        theme.blockquote.barColor = .systemRed
        editor.controller.theme = theme
        let fragment = try #require(editor.fragment(paragraph: 0) as? MarkdownLayoutFragment)
        #expect(fragment.barColor == .systemRed)
    }

    @Test func continuationDrawsNoMarkerInk() throws {
        let editor = Rendered("- item\n\n  continued")
        let continuation = try #require(editor.fragment(paragraph: 1))
        #expect((continuation as? MarkdownLayoutFragment)?.marker == nil)
    }

    @Test func codeInsideListItemKeepsMarkerAndIndent() throws {
        let editor = Rendered("- ```\n  code\n  ```")
        let fragment = try #require(editor.fragment(paragraph: 0) as? FencedCodeBlockLayoutFragment)
        #expect(fragment.marker?.kind == .bullet("•"))
        let bands = CodeBandPath.leadingOffset(forGroupStartingAt: 0, in: editor.controller.textStorage)
        #expect(bands == Restyler.listIndent)
    }
}
