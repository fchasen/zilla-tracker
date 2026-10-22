import Foundation
import Testing
@testable import Zilla

@Suite("Tag suggestions")
struct TagSuggestionTests {
    private let suggestions = [
        TagSuggestion(name: "perf", detail: "Performance problems"),
        TagSuggestion(name: "fxperf:p1"),
        TagSuggestion(name: "regression", detail: "Used to work"),
        TagSuggestion(name: "access", detail: "Accessibility")
    ]

    @Test func emptyQueryReturnsAllAvailable() {
        let names = TagSuggestion.matches(suggestions, query: "", excluding: ["Regression"]).map(\.name)
        #expect(names == ["perf", "fxperf:p1", "access"])
    }

    @Test func ranksPrefixThenContainsThenDetail() {
        let names = TagSuggestion.matches(suggestions, query: "PERF", excluding: []).map(\.name)
        #expect(names == ["perf", "fxperf:p1"])
        let byDetail = TagSuggestion.matches(suggestions, query: "work", excluding: []).map(\.name)
        #expect(byDetail == ["regression"])
    }

    @Test func ignoresWhiteboardBrackets() {
        let names = TagSuggestion.matches(suggestions, query: "[fxperf", excluding: []).map(\.name)
        #expect(names == ["fxperf:p1"])
    }
}

@MainActor
@Suite("Whiteboard tag history")
struct WhiteboardTagHistoryTests {
    private func makeDefaults() -> UserDefaults {
        let name = "WhiteboardTagHistoryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func recordMovesUsedTagsToFront() {
        let defaults = makeDefaults()
        let history = WhiteboardTagHistory(defaults: defaults)
        history.observe(["[a][b]", "[c]"])
        history.record("[C]")
        #expect(history.tags == ["C", "a", "b"])
        #expect(WhiteboardTagHistory(defaults: defaults).tags == ["C", "a", "b"])
    }

    @Test func observeAppendsOnlyUnknownTags() {
        let history = WhiteboardTagHistory(defaults: makeDefaults())
        history.record("[qf:p3]")
        history.observe(["[QF:P3][sec-survey] notes", ""])
        #expect(history.tags == ["qf:p3", "sec-survey"])
    }
}
