import XCTest
@testable import BugzillaKit

final class BugzillaKitTests: XCTestCase {
    func testClientInitializes() {
        let client = BugzillaClient(
            baseURL: URL(string: "https://bugzilla.mozilla.org")!
        )
        XCTAssertNotNil(client)
    }

    func testBugQueryPresets() {
        XCTAssertEqual(BugQuery.myOpenBugs.assignedTo, ["@me"])
        XCTAssertEqual(BugQuery.myOpenBugs.resolution, ["---"])
        XCTAssertEqual(BugQuery.reportedByMe.reporter, ["@me"])

        let ref = ComponentRef(product: "Firefox", component: "General")
        let q = BugQuery.openIn(component: ref)
        XCTAssertEqual(q.product, ["Firefox"])
        XCTAssertEqual(q.component, ["General"])
        XCTAssertEqual(q.resolution, ["---"])
    }

    func testSubstitutingMeReplacesSentinelInAllUserFields() {
        var q = BugQuery(
            assignedTo: [BugQuery.me],
            reporter: [BugQuery.me, "someone@example.com"],
            cc: [BugQuery.me],
            flagRequestee: BugQuery.me,
            userInvolved: BugQuery.me
        )
        q.flagName = "review"

        let resolved = q.substitutingMe(with: "alice@example.com")
        XCTAssertEqual(resolved.assignedTo, ["alice@example.com"])
        XCTAssertEqual(resolved.reporter, ["alice@example.com", "someone@example.com"])
        XCTAssertEqual(resolved.cc, ["alice@example.com"])
        XCTAssertEqual(resolved.flagRequestee, "alice@example.com")
        XCTAssertEqual(resolved.userInvolved, "alice@example.com")
        XCTAssertEqual(resolved.flagName, "review", "non-user fields untouched")
    }

    func testSubstitutingMeNoOpWhenNoSentinel() {
        let q = BugQuery(assignedTo: ["bob@example.com"])
        let resolved = q.substitutingMe(with: "alice@example.com")
        XCTAssertEqual(resolved.assignedTo, ["bob@example.com"])
    }

    func testMetaBugDetection() {
        let bug = Bug(
            id: 1,
            summary: "Tracking bug",
            status: "NEW",
            resolution: "",
            product: "Firefox",
            component: "General",
            keywords: ["meta"]
        )
        XCTAssertTrue(bug.isMeta)
    }
}
