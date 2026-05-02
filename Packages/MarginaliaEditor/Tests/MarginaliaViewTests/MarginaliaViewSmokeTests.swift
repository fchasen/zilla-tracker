import Testing
@testable import MarginaliaView

@Suite(.serialized) struct MarginaliaViewSmokeTests {
    @Test func highlighterInitializes() throws {
        let h = try Highlighter(dialect: .commonMark)
        #expect(h.dialect == .commonMark)
    }

    @Test func highlighterEmitsRunsForBoldText() throws {
        let h = try Highlighter(dialect: .commonMark)
        let runs = h.runs(for: "**bold**")
        #expect(!runs.isEmpty)
    }
}
