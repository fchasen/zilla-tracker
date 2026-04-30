import XCTest
@testable import SliverHighlight

final class JavaScriptHighlighterTests: XCTestCase {
    func testJavaScriptResourceBundleFindsHighlights() {
        XCTAssertNotNil(CodeLanguage.javascript.bundle)
        let url = CodeLanguage.javascript.bundle?.url(
            forResource: "javascript-highlights", withExtension: "scm", subdirectory: "Queries"
        )
        XCTAssertNotNil(url, "Queries/javascript-highlights.scm not found in resources")
    }

    func testJavaScriptKeywordIsHighlighted() {
        let highlighter = SliverHighlighter(theme: .light)
        let runs = highlighter.runs(for: "var propertyPattern = 1;", language: .javascript)
        XCTAssertFalse(runs.isEmpty, "expected non-empty highlight runs for JS")
    }

    func testJavaScriptDetectionByExtension() {
        XCTAssertEqual(CodeLanguageRegistry.detect(path: "Readability.js").id, CodeLanguage.javascript.id)
        XCTAssertEqual(CodeLanguageRegistry.detect(path: "comp.jsx").id, CodeLanguage.javascript.id)
        XCTAssertEqual(CodeLanguageRegistry.detect(path: "lib.mjs").id, CodeLanguage.javascript.id)
    }

    func testEmptyTextReturnsNoRuns() {
        let highlighter = SliverHighlighter(theme: .light)
        XCTAssertEqual(highlighter.runs(for: "", language: .javascript), [])
    }

    func testTypeScriptDetectionByExtension() {
        XCTAssertEqual(CodeLanguageRegistry.detect(path: "Module.ts").id, CodeLanguage.typescript.id)
        XCTAssertEqual(CodeLanguageRegistry.detect(path: "esm.mts").id, CodeLanguage.typescript.id)
    }

    func testTypeScriptTypeAnnotationIsHighlighted() {
        let highlighter = SliverHighlighter(theme: .light)
        let runs = highlighter.runs(for: "let x: number = 1;", language: .typescript)
        XCTAssertFalse(runs.isEmpty, "expected non-empty highlight runs for TS")
    }

    func testStringLiteralReceivesStringColor() {
        let highlighter = SliverHighlighter(theme: .light)
        let runs = highlighter.runs(for: "let x = \"hi\";", language: .javascript)
        let stringColors = Set(runs.map(\.color))
        XCTAssertTrue(stringColors.contains(HighlightTheme.light.string),
                      "expected string color among runs, got \(runs.map(\.color))")
    }

    func testMarkdownDetectionByExtension() {
        XCTAssertEqual(CodeLanguageRegistry.detect(path: "README.md").id, CodeLanguage.markdown.id)
    }

    func testMarkdownHeadingIsHighlighted() {
        let highlighter = SliverHighlighter(theme: .light)
        let runs = highlighter.runs(for: "# Title\n\nbody", language: .markdown)
        XCTAssertFalse(runs.isEmpty, "expected non-empty highlight runs for markdown")
    }
}
