import XCTest
import SwiftTreeSitter
@testable import MarginaliaSyntax

final class TreeSitterMappingTests: XCTestCase {

    // MARK: - byte ↔ utf16 (UTF-16 byte = 2 × code unit)

    func testByteOffsetASCII() {
        let m = TreeSitterMapping(text: "hello")
        XCTAssertEqual(m.byteOffset(forUTF16: 0), 0)
        XCTAssertEqual(m.byteOffset(forUTF16: 3), 6)
        XCTAssertEqual(m.byteOffset(forUTF16: 5), 10)
    }

    func testByteOffsetEmoji() {
        let m = TreeSitterMapping(text: "a🚀b")
        // 🚀 is 2 UTF-16 code units → 4 UTF-16 bytes
        XCTAssertEqual(m.byteOffset(forUTF16: 0), 0)
        XCTAssertEqual(m.byteOffset(forUTF16: 1), 2)
        XCTAssertEqual(m.byteOffset(forUTF16: 3), 6)
        XCTAssertEqual(m.byteOffset(forUTF16: 4), 8)
    }

    func testByteOffsetCJK() {
        let m = TreeSitterMapping(text: "中文")
        // 中, 文 each = 1 UTF-16 code unit → 2 UTF-16 bytes
        XCTAssertEqual(m.byteOffset(forUTF16: 0), 0)
        XCTAssertEqual(m.byteOffset(forUTF16: 1), 2)
        XCTAssertEqual(m.byteOffset(forUTF16: 2), 4)
    }

    func testUTF16OffsetForByte() {
        let m = TreeSitterMapping(text: "a🚀b")
        XCTAssertEqual(m.utf16Offset(forByte: 0), 0)
        XCTAssertEqual(m.utf16Offset(forByte: 2), 1)
        XCTAssertEqual(m.utf16Offset(forByte: 6), 3)
        XCTAssertEqual(m.utf16Offset(forByte: 8), 4)
    }

    func testRoundTripASCIIAndEmoji() {
        let m = TreeSitterMapping(text: "hello 🚀 world\nfoo bar")
        var utf16Off = 0
        for scalar in m.text.unicodeScalars {
            let byte = m.byteOffset(forUTF16: utf16Off)
            XCTAssertEqual(m.utf16Offset(forByte: byte), utf16Off)
            utf16Off += scalar.utf16.count
        }
        let endByte = m.byteOffset(forUTF16: utf16Off)
        XCTAssertEqual(m.utf16Offset(forByte: endByte), utf16Off)
    }

    // MARK: - points

    func testPointSingleLine() {
        let m = TreeSitterMapping(text: "hello")
        XCTAssertEqual(m.point(forByte: 0), Point(row: 0, column: 0))
        XCTAssertEqual(m.point(forByte: 6), Point(row: 0, column: 6))
        XCTAssertEqual(m.point(forByte: 10), Point(row: 0, column: 10))
    }

    func testPointAcrossNewlines() {
        let m = TreeSitterMapping(text: "hello\nworld")
        // \n is at utf16=5 → byte 10
        XCTAssertEqual(m.point(forByte: 10), Point(row: 0, column: 10))
        XCTAssertEqual(m.point(forByte: 12), Point(row: 1, column: 0))
        XCTAssertEqual(m.point(forByte: 22), Point(row: 1, column: 10))
    }

    func testPointInMultilineEmoji() {
        // "🚀\n🚀": 🚀 = 2 utf16 = 4 bytes; \n = 1 utf16 = 2 bytes
        let m = TreeSitterMapping(text: "🚀\n🚀")
        XCTAssertEqual(m.point(forByte: 0), Point(row: 0, column: 0))
        XCTAssertEqual(m.point(forByte: 4), Point(row: 0, column: 4))   // before \n
        XCTAssertEqual(m.point(forByte: 6), Point(row: 1, column: 0))   // after \n
        XCTAssertEqual(m.point(forByte: 10), Point(row: 1, column: 4))
    }

    // MARK: - tsRange

    func testTSRangeCoversEmoji() {
        let m = TreeSitterMapping(text: "a🚀b")
        let nsRange = NSRange(location: 1, length: 2)
        let r = m.tsRange(for: nsRange)
        XCTAssertEqual(r.lowerBound, 2)
        XCTAssertEqual(r.upperBound, 6)
    }

    // MARK: - InputEdit

    func testInputEditAppendASCII() {
        let m = TreeSitterMapping(text: "hello")
        let edit = m.makeInputEdit(replacing: NSRange(location: 5, length: 0), with: " world")
        XCTAssertEqual(edit.startByte, 10)
        XCTAssertEqual(edit.oldEndByte, 10)
        XCTAssertEqual(edit.newEndByte, 22)
        XCTAssertEqual(edit.startPoint, Point(row: 0, column: 10))
        XCTAssertEqual(edit.oldEndPoint, Point(row: 0, column: 10))
        XCTAssertEqual(edit.newEndPoint, Point(row: 0, column: 22))
    }

    func testInputEditReplaceASCII() {
        let m = TreeSitterMapping(text: "hello world")
        let edit = m.makeInputEdit(replacing: NSRange(location: 6, length: 5), with: "Earth")
        XCTAssertEqual(edit.startByte, 12)
        XCTAssertEqual(edit.oldEndByte, 22)
        XCTAssertEqual(edit.newEndByte, 22)
        XCTAssertEqual(edit.newEndPoint, Point(row: 0, column: 22))
    }

    func testInputEditInsertNewline() {
        let m = TreeSitterMapping(text: "hello")
        let edit = m.makeInputEdit(replacing: NSRange(location: 5, length: 0), with: "\nworld")
        XCTAssertEqual(edit.newEndPoint, Point(row: 1, column: 10))
    }

    func testInputEditDeletion() {
        let m = TreeSitterMapping(text: "hello world")
        let edit = m.makeInputEdit(replacing: NSRange(location: 5, length: 6), with: "")
        XCTAssertEqual(edit.startByte, 10)
        XCTAssertEqual(edit.oldEndByte, 22)
        XCTAssertEqual(edit.newEndByte, 10)
        XCTAssertEqual(edit.newEndPoint, Point(row: 0, column: 10))
    }

    func testInputEditWithEmojiInReplacement() {
        let m = TreeSitterMapping(text: "ab")
        let edit = m.makeInputEdit(replacing: NSRange(location: 1, length: 0), with: "🚀")
        XCTAssertEqual(edit.startByte, 2)
        XCTAssertEqual(edit.oldEndByte, 2)
        XCTAssertEqual(edit.newEndByte, 6)
        XCTAssertEqual(edit.newEndPoint, Point(row: 0, column: 6))
    }

    func testInputEditMultiLineEdit() {
        let m = TreeSitterMapping(text: "first\nsecond")
        let edit = m.makeInputEdit(replacing: NSRange(location: 6, length: 6), with: "new\nthird")
        XCTAssertEqual(edit.startPoint, Point(row: 1, column: 0))
        XCTAssertEqual(edit.oldEndPoint, Point(row: 1, column: 12))
        XCTAssertEqual(edit.newEndPoint, Point(row: 2, column: 10))
    }
}
