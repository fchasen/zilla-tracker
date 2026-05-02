import XCTest
import MarginaliaSyntax
import MarginaliaRendering
@testable import MarginaliaView
#if canImport(AppKit) && os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

final class LayoutFragmentTests: XCTestCase {

    func testCodeBlockGetsDefaultFragment() throws {
        let c = try EditorController(initialText: "```\nlet x = 1\n```\n")
        c.refreshNow()

        let fragments = collectFragments(in: c)
        XCTAssertFalse(fragments.contains { $0 is BlockquoteLayoutFragment })
        XCTAssertFalse(fragments.contains { $0 is HorizontalRuleLayoutFragment })
    }

    func testBlockquoteGetsBlockquoteFragment() throws {
        let c = try EditorController(initialText: "> a quote\n")
        c.refreshNow()

        let fragments = collectFragments(in: c)
        XCTAssertTrue(fragments.contains { $0 is BlockquoteLayoutFragment },
                      "expected BlockquoteLayoutFragment for block_quote: \(fragments.map(\.self))")
    }

    func testThematicBreakGetsHorizontalRuleFragment() throws {
        let c = try EditorController(initialText: "---\n")
        c.refreshNow()

        let fragments = collectFragments(in: c)
        XCTAssertTrue(fragments.contains { $0 is HorizontalRuleLayoutFragment },
                      "expected HorizontalRuleLayoutFragment for thematic_break: \(fragments.map(\.self))")
    }

    func testParagraphGetsDefaultFragment() throws {
        let c = try EditorController(initialText: "just prose\n")
        c.refreshNow()

        let fragments = collectFragments(in: c)
        XCTAssertFalse(fragments.contains { $0 is BlockquoteLayoutFragment })
        XCTAssertFalse(fragments.contains { $0 is HorizontalRuleLayoutFragment })
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
