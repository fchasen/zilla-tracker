import Testing
import MarginaliaSyntax
import MarginaliaRendering
@testable import MarginaliaView
#if canImport(AppKit) && os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

@Suite(.serialized) struct LayoutFragmentTests {

    @Test func fencedCodeBlockDispatchesFencedFragment() throws {
        // Caret on the first line so the active-line reveal keeps its
        // markdown verbatim — that's where the layout fragment paints chrome.
        let c = try EditorController(initialText: "```\nlet x = 1\n```\n")
        c.selection = NSRange(location: 0, length: 0)
        c.refreshNow()

        let fragments = collectFragments(in: c)
        let fenced = fragments.compactMap { $0 as? FencedCodeBlockLayoutFragment }
        #expect(fenced.count >= 1, "expected FencedCodeBlockLayoutFragment, got \(fragments.map(\.self))")
        #expect(fenced.contains { $0.isFirstLine })
        #expect(fenced.contains { $0.isLastLine })
    }

    @Test func fencedCodeBlockExposesLanguage() throws {
        let c = try EditorController(initialText: "```swift\nlet x = 1\n```\n")
        c.selection = NSRange(location: 0, length: 0)
        c.refreshNow()

        let fragments = collectFragments(in: c)
        let fenced = fragments.compactMap { $0 as? FencedCodeBlockLayoutFragment }
        #expect(fenced.first?.language == "swift")
    }

    @Test func indentedCodeBlockDispatchesIndentedFragment() throws {
        let c = try EditorController(initialText: "    let x = 1\n    let y = 2\n")
        c.selection = NSRange(location: 0, length: 0)
        c.refreshNow()

        let fragments = collectFragments(in: c)
        let indented = fragments.compactMap { $0 as? IndentedCodeBlockLayoutFragment }
        #expect(indented.count >= 1, "expected IndentedCodeBlockLayoutFragment, got \(fragments.map(\.self))")
    }

    @Test func pipeTableDispatchesPipeTableFragment() throws {
        let source = "| a | b |\n|---|---|\n| 1 | 2 |\n"
        let c = try EditorController(initialText: source)
        c.selection = NSRange(location: 0, length: 0)
        c.refreshNow()

        let fragments = collectFragments(in: c)
        let pipe = fragments.compactMap { $0 as? PipeTableLayoutFragment }
        #expect(pipe.count >= 1, "expected PipeTableLayoutFragment, got \(fragments.map(\.self))")
        #expect(pipe.contains { $0.isFirstLine })
        #expect(pipe.contains { $0.isLastLine })
    }

    @Test func blockquoteGetsBlockquoteFragment() throws {
        let c = try EditorController(initialText: "> a quote\n")
        c.refreshNow()

        let fragments = collectFragments(in: c)
        #expect(fragments.contains { $0 is BlockquoteLayoutFragment },
                "expected BlockquoteLayoutFragment for block_quote: \(fragments.map(\.self))")
    }

    @Test func thematicBreakGetsHorizontalRuleFragment() throws {
        let c = try EditorController(initialText: "---\n")
        c.refreshNow()

        let fragments = collectFragments(in: c)
        #expect(fragments.contains { $0 is HorizontalRuleLayoutFragment },
                "expected HorizontalRuleLayoutFragment for thematic_break: \(fragments.map(\.self))")
    }

    @Test func paragraphGetsDefaultFragment() throws {
        let c = try EditorController(initialText: "just prose\n")
        c.refreshNow()

        let fragments = collectFragments(in: c)
        #expect(!fragments.contains { $0 is BlockquoteLayoutFragment })
        #expect(!fragments.contains { $0 is HorizontalRuleLayoutFragment })
    }

    private func collectFragments(in controller: EditorController) -> [NSTextLayoutFragment] {
        let layoutManager = controller.layoutManager
        layoutManager.ensureLayout(for: layoutManager.documentRange)
        var collected: [NSTextLayoutFragment] = []
        layoutManager.enumerateTextLayoutFragments(
            from: layoutManager.documentRange.location,
            options: [.ensuresLayout]
        ) { fragment in
            collected.append(fragment)
            return true
        }
        return collected
    }
}
