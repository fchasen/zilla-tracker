import XCTest
import SwiftTreeSitter
@testable import MarginaliaSyntax

final class BlockClassifierTests: XCTestCase {

    private func classify(_ source: String) throws -> [BlockRegion] {
        let p = try MarkdownParser(grammar: .block)
        guard let tree = p.parse(source), let root = tree.rootNode else {
            XCTFail("failed to parse")
            return []
        }
        return BlockClassifier.classify(rootNode: root, mapping: p.mapping)
    }

    func testParagraph() throws {
        let regions = try classify("hello world\n")
        XCTAssertTrue(regions.contains { $0.kind == .paragraph })
    }

    func testAtxHeadingLevels() throws {
        for level in 1...6 {
            let hashes = String(repeating: "#", count: level)
            let regions = try classify("\(hashes) heading\n")
            let headings = regions.filter {
                if case .heading = $0.kind { return true } else { return false }
            }
            XCTAssertEqual(headings.count, 1)
            if case .heading(let l) = headings[0].kind {
                XCTAssertEqual(l, level, "expected level \(level), got \(l)")
            }
        }
    }

    func testSetextHeadings() throws {
        let r1 = try classify("title\n=====\n")
        let h1 = r1.first { if case .setextHeading = $0.kind { return true } else { return false } }
        XCTAssertNotNil(h1)
        if case .setextHeading(let lvl)? = h1?.kind {
            XCTAssertEqual(lvl, 1)
        }

        let r2 = try classify("title\n-----\n")
        let h2 = r2.first { if case .setextHeading = $0.kind { return true } else { return false } }
        XCTAssertNotNil(h2)
        if case .setextHeading(let lvl)? = h2?.kind {
            XCTAssertEqual(lvl, 2)
        }
    }

    func testFencedCodeBlockNoLanguage() throws {
        let regions = try classify("```\nlet x = 1\n```\n")
        let code = regions.first { if case .fencedCode = $0.kind { return true } else { return false } }
        XCTAssertNotNil(code)
        if case .fencedCode(let lang)? = code?.kind {
            XCTAssertNil(lang)
        }
    }

    func testFencedCodeBlockWithLanguage() throws {
        let regions = try classify("```swift\nlet x = 1\n```\n")
        let code = regions.first { if case .fencedCode = $0.kind { return true } else { return false } }
        XCTAssertNotNil(code)
        if case .fencedCode(let lang)? = code?.kind {
            XCTAssertEqual(lang, "swift")
        }
    }

    func testIndentedCodeBlock() throws {
        let regions = try classify("    code\n")
        XCTAssertTrue(regions.contains { $0.kind == .indentedCode })
    }

    func testBlockquoteDepth() throws {
        let r1 = try classify("> quoted\n")
        let bq1 = r1.first { if case .blockquote = $0.kind { return true } else { return false } }
        XCTAssertNotNil(bq1)
        if case .blockquote(let d)? = bq1?.kind {
            XCTAssertEqual(d, 1)
        }

        let r2 = try classify("> > nested\n")
        let depths = r2.compactMap { region -> Int? in
            if case .blockquote(let d) = region.kind { return d } else { return nil }
        }
        XCTAssertEqual(depths.sorted(), [1, 2])
    }

    func testUnorderedList() throws {
        let regions = try classify("- one\n- two\n")
        XCTAssertTrue(regions.contains { $0.kind == .unorderedList })
    }

    func testOrderedList() throws {
        let regions = try classify("1. one\n2. two\n")
        XCTAssertTrue(regions.contains { $0.kind == .orderedList })
    }

    func testTaskList() throws {
        let regions = try classify("- [ ] todo\n- [x] done\n")
        XCTAssertTrue(regions.contains { $0.kind == .taskList })
    }

    func testHorizontalRule() throws {
        let regions = try classify("---\n")
        XCTAssertTrue(regions.contains { $0.kind == .horizontalRule })
    }

    func testRangesAreInUTF16Offsets() throws {
        // Headings starting after an emoji — verify the range is in UTF-16
        // (where 🚀 takes 2 code units), not bytes (where it takes 4).
        let source = "🚀\n# heading\n"
        let regions = try classify(source)
        let heading = regions.first { if case .heading = $0.kind { return true } else { return false } }
        XCTAssertNotNil(heading)
        // 🚀 = utf16 length 2, then \n = 1, so heading starts at utf16 offset 3
        XCTAssertEqual(heading?.range.location, 3)
    }

    func testMixedDocumentEnumeration() throws {
        let source = """
        # heading

        paragraph

        ```swift
        code
        ```

        - bullet

        > quote
        """
        let regions = try classify(source)
        let kinds = regions.map { $0.kind }
        XCTAssertTrue(kinds.contains(where: { if case .heading(level: 1) = $0 { return true } else { return false } }))
        XCTAssertTrue(kinds.contains(.paragraph))
        XCTAssertTrue(kinds.contains(where: { if case .fencedCode = $0 { return true } else { return false } }))
        XCTAssertTrue(kinds.contains(.unorderedList))
        XCTAssertTrue(kinds.contains(where: { if case .blockquote = $0 { return true } else { return false } }))
    }
}
