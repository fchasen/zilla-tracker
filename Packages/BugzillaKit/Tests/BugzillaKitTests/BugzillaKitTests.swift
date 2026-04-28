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
        q.flagNames = ["review"]

        let resolved = q.substitutingMe(with: "alice@example.com")
        XCTAssertEqual(resolved.assignedTo, ["alice@example.com"])
        XCTAssertEqual(resolved.reporter, ["alice@example.com", "someone@example.com"])
        XCTAssertEqual(resolved.cc, ["alice@example.com"])
        XCTAssertEqual(resolved.flagRequestee, "alice@example.com")
        XCTAssertEqual(resolved.userInvolved, "alice@example.com")
        XCTAssertEqual(resolved.flagNames, ["review"], "non-user fields untouched")
    }

    func testSubstitutingMeNoOpWhenNoSentinel() {
        let q = BugQuery(assignedTo: ["bob@example.com"])
        let resolved = q.substitutingMe(with: "alice@example.com")
        XCTAssertEqual(resolved.assignedTo, ["bob@example.com"])
    }

    func testPhabricatorPatchDetection() {
        let phab = Attachment(id: 1, contentType: "text/x-phabricator-request", isObsolete: false)
        let phabObsolete = Attachment(id: 2, contentType: "text/x-phabricator-request", isObsolete: true)
        let other = Attachment(id: 3, contentType: "text/plain", isObsolete: false)

        let bug = Bug(
            id: 1, summary: "x", status: "NEW", resolution: "",
            product: "P", component: "C",
            attachments: [phabObsolete, other, phab]
        )
        XCTAssertTrue(bug.hasPhabricatorPatch)

        let bugNoPatch = Bug(
            id: 2, summary: "y", status: "NEW", resolution: "",
            product: "P", component: "C",
            attachments: [phabObsolete, other]
        )
        XCTAssertFalse(bugNoPatch.hasPhabricatorPatch)

        let bare = Bug(id: 3, summary: "z", status: "NEW", resolution: "", product: "P", component: "C")
        XCTAssertFalse(bare.hasPhabricatorPatch)
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
