import XCTest
@testable import FolioHighlight

final class CodeLanguageRegistryTests: XCTestCase {
    func testUnknownExtensionFallsBackToPlain() {
        XCTAssertEqual(CodeLanguageRegistry.detect(path: "foo.unknownext").id, CodeLanguage.plain.id)
    }

    func testEmptyPathIsPlain() {
        XCTAssertEqual(CodeLanguageRegistry.detect(path: "").id, CodeLanguage.plain.id)
    }

    func testExtensionlessFilenameIsPlain() {
        XCTAssertEqual(CodeLanguageRegistry.detect(path: "Makefile").id, CodeLanguage.plain.id)
    }

    func testEmptyHighlighterReturnsNoRunsForPlain() {
        let highlighter = FolioHighlighter(theme: .light)
        XCTAssertEqual(highlighter.runs(for: "let x = 1", language: .plain), [])
    }
}
