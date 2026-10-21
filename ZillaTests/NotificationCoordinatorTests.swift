#if os(macOS)
import Foundation
import Testing
import UserNotifications
@testable import Zilla

private func makeDefaults() -> UserDefaults {
    let suite = "NotificationCoordinatorTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

private func makeCandidate(
    _ category: NotificationCategory = .patch,
    itemID: Int = 224113,
    url: URL = URL(string: "https://phabricator.services.mozilla.com/D224113")!
) -> NotificationCandidate {
    NotificationCandidate(
        category: category,
        itemID: itemID,
        eventDate: Date(timeIntervalSince1970: 1_800_000_000),
        title: "mconley accepted your revision",
        subtitle: "D\(itemID)",
        body: "Bug 1910022 - Tidy toolbar layout",
        url: url
    )
}

@MainActor
struct NotificationSettingsTests {
    @Test func allCategoriesEnabledByDefault() {
        #expect(NotificationSettings.enabledCategories(makeDefaults()) == Set(NotificationCategory.allCases))
    }

    @Test func disabledCategoryIsExcluded() {
        let defaults = makeDefaults()
        defaults.set(false, forKey: NotificationSettings.reviewKey)
        #expect(NotificationSettings.enabledCategories(defaults) == [.needinfo, .patch])
    }

    @Test func keysMatchCategories() {
        #expect(NotificationSettings.key(for: .needinfo) == "zilla.notifications.needinfo")
        #expect(NotificationSettings.key(for: .review) == "zilla.notifications.review")
        #expect(NotificationSettings.key(for: .patch) == "zilla.notifications.patch")
    }
}

@MainActor
struct NotificationPayloadTests {
    @Test func roundTripsThroughUserInfo() {
        let payload = NotificationPayload(category: "needinfo", itemID: 42, url: URL(string: "https://bugzilla.mozilla.org/show_bug.cgi?id=42"))
        #expect(NotificationPayload(userInfo: payload.userInfo) == payload)
    }

    @Test func roundTripsWithoutURL() {
        let payload = NotificationPayload(category: "review", itemID: 7, url: nil)
        #expect(NotificationPayload(userInfo: payload.userInfo) == payload)
    }

    @Test func missingKeysDecodeToNil() {
        #expect(NotificationPayload(userInfo: ["category": "patch"]) == nil)
        #expect(NotificationPayload(userInfo: ["itemID": 3]) == nil)
    }

    @Test func candidatePayloadCarriesCategoryItemAndURL() {
        let candidate = makeCandidate()
        let payload = NotificationCoordinator.payload(for: candidate)
        #expect(payload == NotificationPayload(category: "patch", itemID: 224113, url: candidate.url))
    }
}

@MainActor
struct NotificationTargetTests {
    @Test func payloadWins() {
        let url = URL(string: "https://example.invalid/custom")!
        let target = NotificationCoordinator.target(
            identifier: "review-1",
            payload: NotificationPayload(category: "patch", itemID: 9, url: url)
        )
        #expect(target == NotificationTarget(category: .patch, itemID: 9, url: url))
    }

    @Test func payloadWithoutURLUsesDefault() {
        let target = NotificationCoordinator.target(
            identifier: "needinfo-5",
            payload: NotificationPayload(category: "needinfo", itemID: 5, url: nil)
        )
        #expect(target?.url == URL(string: "https://bugzilla.mozilla.org/show_bug.cgi?id=5"))
    }

    @Test func fallsBackToIdentifier() {
        let target = NotificationCoordinator.target(identifier: "patch-224113", payload: nil)
        #expect(target == NotificationTarget(
            category: .patch,
            itemID: 224113,
            url: URL(string: "https://phabricator.services.mozilla.com/D224113")!
        ))
    }

    @Test func unknownPayloadCategoryFallsBackToIdentifier() {
        let target = NotificationCoordinator.target(
            identifier: "review-12",
            payload: NotificationPayload(category: "bogus", itemID: 99, url: nil)
        )
        #expect(target?.category == .review)
        #expect(target?.itemID == 12)
    }

    @Test func malformedIdentifierYieldsNil() {
        #expect(NotificationCoordinator.target(identifier: "nonsense", payload: nil) == nil)
        #expect(NotificationCoordinator.target(identifier: "review-abc", payload: nil) == nil)
    }
}

@MainActor
struct NotificationDetailRouteTests {
    @Test func detailPathWins() {
        let route = NotificationCoordinator.detailRoute(
            detailPath: [.revision(3), .bug(8)],
            activeRevisionID: 4,
            selectedBugID: 5,
            sidebarSelection: .smart(.myBugs)
        )
        #expect(route == .bug(8))
    }

    @Test func activeRevisionBeatsSelectedBug() {
        let route = NotificationCoordinator.detailRoute(
            detailPath: [],
            activeRevisionID: 4,
            selectedBugID: 5,
            sidebarSelection: .smart(.myBugs)
        )
        #expect(route == .revision(4))
    }

    @Test func selectedBugWhenNothingElse() {
        let route = NotificationCoordinator.detailRoute(
            detailPath: [],
            activeRevisionID: nil,
            selectedBugID: 5,
            sidebarSelection: .smart(.needsReview)
        )
        #expect(route == .bug(5))
    }

    @Test func draftsSelectionHidesSelectedBug() {
        let route = NotificationCoordinator.detailRoute(
            detailPath: [],
            activeRevisionID: nil,
            selectedBugID: 5,
            sidebarSelection: .allDrafts
        )
        #expect(route == nil)
    }

    @Test func bugRouteSuppressesNeedinfo() {
        #expect(NotificationCoordinator.identifiers(for: .bug(5)) == ["needinfo-5"])
    }

    @Test func revisionRouteSuppressesReviewAndPatch() {
        #expect(NotificationCoordinator.identifiers(for: .revision(7)) == ["review-7", "patch-7"])
    }

    @Test func draftAndNilSuppressNothing() {
        #expect(NotificationCoordinator.identifiers(for: .draft(UUID())).isEmpty)
        #expect(NotificationCoordinator.identifiers(for: nil).isEmpty)
    }
}

@MainActor
struct NotificationRoutingTests {
    @Test func needinfoSelectsNeedsInfoAndBug() {
        let workspace = Workspace()
        workspace.activeRevisionID = 3
        NotificationCoordinator.route(
            NotificationTarget(category: .needinfo, itemID: 1923456, url: NotificationCoordinator.defaultURL(for: .needinfo, itemID: 1923456)),
            in: workspace
        )
        #expect(workspace.sidebarSelection == .smart(.needsReview))
        #expect(workspace.selectedBugID == 1923456)
        #expect(workspace.activeRevisionID == nil)
    }

    @Test func needinfoClearsActiveRevisionWhenBugAlreadySelected() {
        let workspace = Workspace()
        workspace.sidebarSelection = .smart(.needsReview)
        workspace.selectedBugID = 10
        workspace.activeRevisionID = 3
        workspace.detailPath = [.revision(3)]
        NotificationCoordinator.route(
            NotificationTarget(category: .needinfo, itemID: 10, url: NotificationCoordinator.defaultURL(for: .needinfo, itemID: 10)),
            in: workspace
        )
        #expect(workspace.selectedBugID == 10)
        #expect(workspace.activeRevisionID == nil)
        #expect(workspace.detailPath.isEmpty)
    }

    @Test func reviewSelectsReviewsAndRevision() {
        let workspace = Workspace()
        NotificationCoordinator.route(
            NotificationTarget(category: .review, itemID: 224113, url: NotificationCoordinator.defaultURL(for: .review, itemID: 224113)),
            in: workspace
        )
        #expect(workspace.sidebarSelection == .revisions(.reviews))
        #expect(workspace.activeRevisionID == 224113)
    }

    @Test func patchSelectsPatchesAndRevision() {
        let workspace = Workspace()
        workspace.detailPath = [.bug(1)]
        NotificationCoordinator.route(
            NotificationTarget(category: .patch, itemID: 223901, url: NotificationCoordinator.defaultURL(for: .patch, itemID: 223901)),
            in: workspace
        )
        #expect(workspace.sidebarSelection == .revisions(.patches))
        #expect(workspace.activeRevisionID == 223901)
        #expect(workspace.detailPath.isEmpty)
    }

    @Test func defaultURLs() {
        #expect(NotificationCoordinator.defaultURL(for: .needinfo, itemID: 1) == URL(string: "https://bugzilla.mozilla.org/show_bug.cgi?id=1"))
        #expect(NotificationCoordinator.defaultURL(for: .review, itemID: 2) == URL(string: "https://phabricator.services.mozilla.com/D2"))
        #expect(NotificationCoordinator.defaultURL(for: .patch, itemID: 3) == URL(string: "https://phabricator.services.mozilla.com/D3"))
    }
}

@MainActor
struct NotificationContentTests {
    @Test func requestCarriesContentAndThreading() {
        let candidate = makeCandidate()
        let request = NotificationCoordinator.request(for: candidate)
        #expect(request.identifier == "patch-224113")
        #expect(request.trigger == nil)
        #expect(request.content.title == candidate.title)
        #expect(request.content.subtitle == candidate.subtitle)
        #expect(request.content.body == candidate.body)
        #expect(request.content.threadIdentifier == "patch")
        #expect(request.content.categoryIdentifier == "patch")
        #expect(request.content.sound != nil)
        #expect(NotificationPayload(userInfo: request.content.userInfo) == NotificationCoordinator.payload(for: candidate))
    }

    @Test func categoriesCarryBothActions() {
        let categories = NotificationCoordinator.categories
        #expect(Set(categories.map(\.identifier)) == ["needinfo", "review", "patch"])
        for category in categories {
            #expect(category.actions.map(\.identifier) == ["mark-seen", "open-browser"])
            #expect(category.actions.allSatisfy { !$0.options.contains(.foreground) })
        }
    }

    @Test func postingRequiresAuthorization() {
        #expect(NotificationCoordinator.canPost(.authorized))
        #expect(NotificationCoordinator.canPost(.provisional))
        #expect(!NotificationCoordinator.canPost(.denied))
        #expect(!NotificationCoordinator.canPost(.notDetermined))
    }
}

@MainActor
struct NotificationLedgerStorageTests {
    @Test func missingLedgerLoadsEmpty() {
        #expect(NotificationCoordinator.loadLedger(from: makeDefaults()) == NotificationLedger())
    }

    @Test func ledgerRoundTrips() {
        let defaults = makeDefaults()
        var ledger = NotificationLedger()
        ledger.entries["needinfo-5"] = NotifiedEntry(
            eventDate: Date(timeIntervalSince1970: 1_800_000_000),
            recordedAt: Date(timeIntervalSince1970: 1_800_000_100)
        )
        ledger.baselined = [.needinfo, .patch]
        NotificationCoordinator.saveLedger(ledger, to: defaults)
        #expect(NotificationCoordinator.loadLedger(from: defaults) == ledger)
    }

    @Test func corruptLedgerLoadsEmpty() {
        let defaults = makeDefaults()
        defaults.set(Data("not json".utf8), forKey: NotificationCoordinator.ledgerKey)
        #expect(NotificationCoordinator.loadLedger(from: defaults) == NotificationLedger())
    }
}
#endif
