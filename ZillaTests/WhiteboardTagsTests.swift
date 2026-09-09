import Foundation
import Testing
@testable import Zilla

@Suite("Whiteboard parsing")
struct WhiteboardParsingTests {
    @Test func parsesBracketedTags() {
        let board = Whiteboard("[fxperf:p1][qf:p3]")
        #expect(board.tags == ["fxperf:p1", "qf:p3"])
        #expect(board.freeText.isEmpty)
    }

    @Test func keepsFreeTextSeparateFromTags() {
        let board = Whiteboard("[sec-survey] needs a follow-up")
        #expect(board.tags == ["sec-survey"])
        #expect(board.freeText == "needs a follow-up")
    }

    @Test func preservesOriginalLayout() {
        let raw = "notes [a] more [b]"
        #expect(Whiteboard(raw).rawValue == raw)
    }

    @Test func normalizesWhitespaceInsideTags() {
        #expect(Whiteboard("[sec-survey  done]").tags == ["sec-survey done"])
    }

    @Test func treatsUnterminatedBracketAsText() {
        let board = Whiteboard("[oops")
        #expect(board.tags.isEmpty)
        #expect(board.rawValue == "[oops")
    }

    @Test func dropsEmptyBrackets() {
        #expect(Whiteboard("[][a]").tags == ["a"])
    }

    @Test func emptyWhiteboard() {
        #expect(Whiteboard(nil).isEmpty)
        #expect(Whiteboard("   ").isEmpty)
    }
}

@Suite("Whiteboard editing")
struct WhiteboardEditingTests {
    @Test func addsTagToEmptyWhiteboard() {
        var board = Whiteboard(nil)
        board.add("fxperf:p1")
        #expect(board.rawValue == "[fxperf:p1]")
    }

    @Test func addsTagAfterExistingTags() {
        var board = Whiteboard("[a]")
        board.add("b")
        #expect(board.rawValue == "[a][b]")
    }

    @Test func separatesNewTagFromFreeText() {
        var board = Whiteboard("notes")
        board.add("a")
        #expect(board.rawValue == "notes [a]")
    }

    @Test func ignoresDuplicateTagsRegardlessOfCase() {
        var board = Whiteboard("[Fxperf:p1]")
        board.add("fxperf:p1")
        #expect(board.tags == ["Fxperf:p1"])
    }

    @Test func addsEveryTagInPastedInput() {
        var board = Whiteboard(nil)
        board.add("[a][b] c")
        #expect(board.tags == ["a", "b", "c"])
    }

    @Test func ignoresBlankInput() {
        var board = Whiteboard("[a]")
        board.add("   ")
        #expect(board.rawValue == "[a]")
    }

    @Test func removesTagAndTidiesSpacing() {
        var board = Whiteboard("[a] [b]")
        board.remove("a")
        #expect(board.rawValue == "[b]")
    }

    @Test func removeKeepsFreeText() {
        var board = Whiteboard("[a] needs triage")
        board.remove("a")
        #expect(board.rawValue == "needs triage")
    }

    @Test func replaceKeepsPosition() {
        var board = Whiteboard("[a][b]")
        board.replace("a", with: "c")
        #expect(board.tags == ["c", "b"])
    }

    @Test func replaceWithEmptyRemovesTag() {
        var board = Whiteboard("[a][b]")
        board.replace("a", with: "  ")
        #expect(board.tags == ["b"])
    }

    @Test func replaceCollapsesIntoExistingDuplicate() {
        var board = Whiteboard("[a][b]")
        board.replace("b", with: "a")
        #expect(board.tags == ["a"])
    }

    @Test func replaceStripsPastedBrackets() {
        var board = Whiteboard("[a]")
        board.replace("a", with: "[b]")
        #expect(board.tags == ["b"])
    }

    @Test func setFreeTextReplacesExistingText() {
        var board = Whiteboard("notes [a] trailing")
        board.setFreeText("only")
        #expect(board.rawValue == "only [a]")
    }

    @Test func setFreeTextToEmptyDropsText() {
        var board = Whiteboard("[a] notes")
        board.setFreeText("")
        #expect(board.rawValue == "[a]")
    }

    @Test func setFreeTextOnTagOnlyWhiteboard() {
        var board = Whiteboard("[a]")
        board.setFreeText("notes")
        #expect(board.rawValue == "[a] notes")
    }
}
