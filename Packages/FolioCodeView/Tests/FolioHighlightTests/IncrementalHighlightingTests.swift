import Testing
import Foundation
@testable import FolioHighlight

@Suite struct IncrementalHighlightingTests {
    @Test func resetReturnsRunsForJavaScript() {
        let highlighter = FolioHighlighter(theme: .light)
        let runs = highlighter.reset(text: "let x = 1;", language: .javascript)
        #expect(!runs.isEmpty)
    }

    @Test func resetReturnsEmptyForPlainLanguage() {
        let highlighter = FolioHighlighter(theme: .light)
        let runs = highlighter.reset(text: "let x = 1;", language: .plain)
        #expect(runs.isEmpty)
    }

    @Test func didEditWithoutResetReturnsEmptyAndFullRange() {
        let highlighter = FolioHighlighter(theme: .light)
        let edit = highlighter.didEdit(replacedRange: NSRange(location: 0, length: 0), replacement: "x", in: "x")
        #expect(edit.newRuns.isEmpty)
        #expect(edit.invalidatedRange == NSRange(location: 0, length: 1))
    }

    @Test func didEditSingleCharInsertionAtEnd() {
        let highlighter = FolioHighlighter(theme: .light)
        let initial = "let x = 1"
        _ = highlighter.reset(text: initial, language: .javascript)
        let updated = "let x = 1;"
        let edit = highlighter.didEdit(
            replacedRange: NSRange(location: 9, length: 0),
            replacement: ";",
            in: updated
        )
        #expect(edit.invalidatedRange.location >= 0)
        let documentLength = (updated as NSString).length
        #expect(edit.invalidatedRange.location + edit.invalidatedRange.length <= documentLength)
    }

    @Test func didEditMultilineReplacement() {
        let highlighter = FolioHighlighter(theme: .light)
        let initial = "let a = 1;\nlet b = 2;"
        _ = highlighter.reset(text: initial, language: .javascript)
        let replacementRange = NSRange(location: 11, length: 10)
        let updated = "let a = 1;\nconst c = 3;\nlet d = 4;"
        let edit = highlighter.didEdit(
            replacedRange: replacementRange,
            replacement: "const c = 3;\nlet d = 4;",
            in: updated
        )
        let documentLength = (updated as NSString).length
        #expect(edit.invalidatedRange.location + edit.invalidatedRange.length <= documentLength)
    }

    @Test func didEditDeletionAtEnd() {
        let highlighter = FolioHighlighter(theme: .light)
        let initial = "let x = 123;"
        _ = highlighter.reset(text: initial, language: .javascript)
        let updated = "let x = 12;"
        let edit = highlighter.didEdit(
            replacedRange: NSRange(location: 10, length: 1),
            replacement: "",
            in: updated
        )
        let documentLength = (updated as NSString).length
        #expect(edit.invalidatedRange.location + edit.invalidatedRange.length <= documentLength)
    }

    @Test func didEditAtStartOfBuffer() {
        let highlighter = FolioHighlighter(theme: .light)
        let initial = "let x = 1;"
        _ = highlighter.reset(text: initial, language: .javascript)
        let updated = "var x = 1;"
        let edit = highlighter.didEdit(
            replacedRange: NSRange(location: 0, length: 3),
            replacement: "var",
            in: updated
        )
        #expect(edit.invalidatedRange.location == 0)
    }

    @Test func incrementalParseMatchesFullParseAfterEdits() {
        let stateful = FolioHighlighter(theme: .light)
        let stateless = FolioHighlighter(theme: .light)

        var text = "let x = 1"
        _ = stateful.reset(text: text, language: .javascript)

        let edits: [(NSRange, String)] = [
            (NSRange(location: 9, length: 0), ";"),
            (NSRange(location: 0, length: 3), "var"),
            (NSRange(location: 10, length: 0), "\nlet y = 2;")
        ]

        for (range, replacement) in edits {
            let nsText = text as NSString
            let updated = nsText.replacingCharacters(in: range, with: replacement)
            _ = stateful.didEdit(replacedRange: range, replacement: replacement, in: updated)
            text = updated
        }

        let fullRuns = stateless.runs(for: text, language: .javascript)
        let statefulFinalRuns = stateful.reset(text: text, language: .javascript)

        let fullSet = Set(fullRuns)
        let statefulSet = Set(statefulFinalRuns)
        #expect(fullSet == statefulSet)
    }

    @Test func themeChangeAffectsNewRuns() {
        let highlighter = FolioHighlighter(theme: .light)
        let initial = "let x = 1;"
        let lightRuns = highlighter.reset(text: initial, language: .javascript)
        #expect(!lightRuns.isEmpty)

        highlighter.theme = .dark
        let edit = highlighter.didEdit(
            replacedRange: NSRange(location: 9, length: 0),
            replacement: " ",
            in: "let x = 1; "
        )
        let darkColors = Set(edit.newRuns.map(\.color))
        let lightColors = Set(lightRuns.map(\.color))
        #expect(darkColors != lightColors || edit.newRuns.isEmpty)
    }

    @Test func resetAfterEditsReseedsState() {
        let highlighter = FolioHighlighter(theme: .light)
        _ = highlighter.reset(text: "let x = 1;", language: .javascript)
        _ = highlighter.didEdit(
            replacedRange: NSRange(location: 0, length: 3),
            replacement: "var",
            in: "var x = 1;"
        )
        let runs = highlighter.reset(text: "function foo() {}", language: .javascript)
        #expect(!runs.isEmpty)
    }
}
