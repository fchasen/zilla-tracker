import Testing
@testable import Zilla
@testable import BugzillaKit

struct ComponentReleaseBoardTests {
    @Test func usesLatestThreeReleaseTargetsAndDefaultsSecondFromLast() {
        let product = Product(
            id: 1,
            name: "Firefox",
            description: "",
            isActive: true,
            components: [],
            defaultMilestone: "150",
            milestones: [
                ProductMilestone(id: 1, name: "---", sortKey: 0),
                ProductMilestone(id: 2, name: "Future", sortKey: 999),
                ProductMilestone(id: 3, name: "149", sortKey: 149),
                ProductMilestone(id: 4, name: "150", sortKey: 150),
                ProductMilestone(id: 5, name: "151", sortKey: 151),
                ProductMilestone(id: 6, name: "152", sortKey: 152)
            ]
        )

        #expect(ReleaseTargetMilestonePlanner.choices(for: product) == ["150", "151", "152"])
        #expect(ReleaseTargetMilestonePlanner.defaultMilestone(for: product) == "151")
    }

    @Test func inspectorChoicesIncludeUnsetLatestTargetsFutureAndCurrent() {
        let product = Product(
            id: 1,
            name: "Firefox",
            description: "",
            isActive: true,
            components: [],
            milestones: [
                ProductMilestone(id: 1, name: "---", sortKey: 0),
                ProductMilestone(id: 2, name: "Future", sortKey: 999),
                ProductMilestone(id: 3, name: "149", sortKey: 149),
                ProductMilestone(id: 4, name: "150", sortKey: 150),
                ProductMilestone(id: 5, name: "151", sortKey: 151),
                ProductMilestone(id: 6, name: "152", sortKey: 152)
            ]
        )

        #expect(ReleaseTargetMilestonePlanner.inspectorChoices(for: product, current: nil) == ["---", "150", "151", "152", "Future"])
        #expect(ReleaseTargetMilestonePlanner.inspectorChoices(for: product, current: "149") == ["---", "149", "150", "151", "152", "Future"])
    }

    @Test func classifiesBoardColumnsByWorkflowPrecedence() {
        #expect(ReleaseBoardPlanner.column(for: bug(id: 1, assignedTo: nil)) == .unassigned)
        #expect(ReleaseBoardPlanner.column(for: bug(id: 2, assignedTo: "dev@mozilla.com")) == .inProgress)
        #expect(ReleaseBoardPlanner.column(for: bug(
            id: 3,
            assignedTo: "dev@mozilla.com",
            attachments: [phabricatorPatch()]
        )) == .inReview)
        #expect(ReleaseBoardPlanner.column(for: bug(
            id: 4,
            status: "RESOLVED",
            resolution: "FIXED",
            flags: [flag(name: "qe-verify", status: "+")]
        )) == .inTesting)
        #expect(ReleaseBoardPlanner.column(for: bug(
            id: 5,
            status: "VERIFIED",
            resolution: "FIXED",
            flags: [flag(name: "qe-verify", status: "+")]
        )) == .done)
        #expect(ReleaseBoardPlanner.column(for: bug(
            id: 6,
            status: "RESOLVED",
            resolution: "WONTFIX"
        )) == .other)
    }

    @Test func updateMappingForTodoAndInProgress() throws {
        let unassignedUpdate = try ReleaseBoardPlanner.update(
            forMoving: bug(id: 1, assignedTo: "dev@mozilla.com"),
            to: .unassigned,
            currentUser: "me@mozilla.com"
        ).get()
        #expect(unassignedUpdate.status == "NEW")
        #expect(unassignedUpdate.assignedTo == "nobody@mozilla.org")

        let progressUpdate = try ReleaseBoardPlanner.update(
            forMoving: bug(id: 2, assignedTo: nil),
            to: .inProgress,
            currentUser: "me@mozilla.com"
        ).get()
        #expect(progressUpdate.status == "ASSIGNED")
        #expect(progressUpdate.assignedTo == "me@mozilla.com")
    }

    @Test func inReviewRequiresPatchAndAssignsCurrentUser() throws {
        let missingPatch = ReleaseBoardPlanner.update(
            forMoving: bug(id: 1, assignedTo: "dev@mozilla.com"),
            to: .inReview,
            currentUser: "me@mozilla.com"
        )
        guard case .failure(.missingPatch) = missingPatch else {
            Issue.record("Expected missing patch failure")
            return
        }

        let update = try ReleaseBoardPlanner.update(
            forMoving: bug(id: 2, assignedTo: nil, attachments: [phabricatorPatch()]),
            to: .inReview,
            currentUser: "me@mozilla.com"
        ).get()
        #expect(update.status == "ASSIGNED")
        #expect(update.assignedTo == "me@mozilla.com")
    }

    @Test func testingAndDoneMapQEVerifyFlags() throws {
        let testingUpdate = try ReleaseBoardPlanner.update(
            forMoving: bug(id: 1),
            to: .inTesting,
            currentUser: "me@mozilla.com"
        ).get()
        #expect(testingUpdate.status == "RESOLVED")
        #expect(testingUpdate.resolution == "FIXED")
        #expect(testingUpdate.flags?.first?.name == "qe-verify")
        #expect(testingUpdate.flags?.first?.status == "+")

        let doneUpdate = try ReleaseBoardPlanner.update(
            forMoving: bug(
                id: 2,
                status: "RESOLVED",
                resolution: "FIXED",
                flags: [flag(id: 44, name: "qe-verify", status: "+")]
            ),
            to: .done,
            currentUser: "me@mozilla.com"
        ).get()
        #expect(doneUpdate.status == "RESOLVED")
        #expect(doneUpdate.resolution == "FIXED")
        #expect(doneUpdate.flags?.first?.id == 44)
        #expect(doneUpdate.flags?.first?.status == "X")
    }

    private func bug(
        id: Int,
        status: String = "NEW",
        resolution: String = "",
        assignedTo: String? = nil,
        flags: [Flag] = [],
        attachments: [BugzillaKit.Attachment] = []
    ) -> BugzillaKit.Bug {
        BugzillaKit.Bug(
            id: id,
            summary: "Bug \(id)",
            status: status,
            resolution: resolution,
            product: "Firefox",
            component: "General",
            assignedTo: assignedTo,
            flags: flags,
            attachments: attachments
        )
    }

    private func flag(id: Int = 1, name: String, status: String) -> Flag {
        Flag(
            id: id,
            name: name,
            status: status,
            setter: nil,
            requestee: nil,
            typeID: nil,
            creationDate: nil,
            modificationDate: nil
        )
    }

    private func phabricatorPatch() -> BugzillaKit.Attachment {
        BugzillaKit.Attachment(id: 1, contentType: "text/x-phabricator-request", isObsolete: false)
    }
}
