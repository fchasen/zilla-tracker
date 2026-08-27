import Testing
@testable import Zilla

@MainActor
struct DraftConsumptionTests {
    @Test func untouchedDraftIsCleared() {
        #expect(DraftConsumption.remainder(after: "Ship it", in: "Ship it") == nil)
    }

    @Test func keepsOnlyTheTextTypedDuringTheRoundTrip() {
        #expect(DraftConsumption.remainder(after: "Ship it", in: "Ship it\n\nAlso needs a test.") == "Also needs a test.")
    }

    @Test func stripsSeparatingWhitespaceButNotTrailingWhitespace() {
        #expect(DraftConsumption.remainder(after: "Ship it", in: "Ship it \n \tAnd more\n\n") == "And more\n\n")
    }

    @Test func whitespaceOnlyAdditionClearsTheDraft() {
        #expect(DraftConsumption.remainder(after: "Ship it", in: "Ship it\n\n   \t\n") == nil)
    }

    @Test func divergentTextIsReturnedUnchanged() {
        let submitted = "Line one\nLine two"
        let current = "Line one edited\nLine two\nLine three"

        let remainder = DraftConsumption.remainder(after: submitted, in: current)

        #expect(remainder != nil)
        #expect(remainder == current)
    }

    @Test func shortenedDraftIsReturnedUnchanged() {
        #expect(DraftConsumption.remainder(after: "Ship it now", in: "Ship it") == "Ship it")
    }

    @Test func submittedTextAppearingLaterIsNotConsumed() {
        #expect(DraftConsumption.remainder(after: "note", in: "a note") == "a note")
    }

    @Test func draftEmptiedDuringTheRoundTripComesBackEmptyRatherThanNil() {
        #expect(DraftConsumption.remainder(after: "Ship it", in: "") == "")
    }

    @Test func emptySubmittedKeepsEverythingTyped() {
        #expect(DraftConsumption.remainder(after: "", in: "Typed while sending") == "Typed while sending")
        #expect(DraftConsumption.remainder(after: "", in: "\n  Typed while sending") == "Typed while sending")
        #expect(DraftConsumption.remainder(after: "", in: "   \n") == nil)
        #expect(DraftConsumption.remainder(after: "", in: "") == nil)
    }

    @Test func multiLineCommentConsumesOnlyTheSubmittedPortion() {
        let submitted = """
        Steps to reproduce:

        1. Open the bug
        2. Click submit
        """
        let current = submitted + "\n\nIt also happens offline."

        #expect(DraftConsumption.remainder(after: submitted, in: current) == "It also happens offline.")
    }

    @Test func multiLineEditAheadOfTheInsertionPointIsPreserved() {
        let submitted = """
        Steps to reproduce:

        1. Open the bug
        2. Click submit
        """
        let current = """
        Steps to reproduce (macOS only):

        1. Open the bug
        2. Click submit
        3. Watch the draft vanish
        """

        let remainder = DraftConsumption.remainder(after: submitted, in: current)

        #expect(remainder != nil)
        #expect(remainder == current)
    }

    @Test func skinToneEmojiIsMatchedAsASingleCharacter() {
        #expect(DraftConsumption.remainder(after: "Looks good 👍🏽", in: "Looks good 👍🏽 — shipping 🎉") == "— shipping 🎉")
    }

    @Test func zeroWidthJoinerSequenceIsMatchedAsASingleCharacter() {
        #expect(DraftConsumption.remainder(after: "👨‍👩‍👧‍👦", in: "👨‍👩‍👧‍👦\n\nready") == "ready")
    }

    @Test func repeatedEmojiIsNotSplitMidSequence() {
        #expect(DraftConsumption.remainder(after: "🎉🎉", in: "🎉🎉🎉") == "🎉")
        #expect(DraftConsumption.remainder(after: "🎉🎉🎉", in: "🎉🎉") == "🎉🎉")
    }

    @Test func nonLatinTextIsConsumedCleanly() {
        #expect(DraftConsumption.remainder(after: "修正しました", in: "修正しました\n\nありがとう") == "ありがとう")
    }
}
