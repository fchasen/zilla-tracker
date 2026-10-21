//
//  NotificationCoordinator.swift
//  Zilla
//

#if os(macOS)
import AppKit
import Observation
import UserNotifications

enum NotificationSettings {
    static let needinfoKey = "zilla.notifications.needinfo"
    static let reviewKey = "zilla.notifications.review"
    static let patchKey = "zilla.notifications.patch"

    static func key(for category: NotificationCategory) -> String {
        switch category {
        case .needinfo: needinfoKey
        case .review: reviewKey
        case .patch: patchKey
        }
    }

    static func isEnabled(_ category: NotificationCategory, in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: key(for: category)) as? Bool ?? true
    }

    static func enabledCategories(_ defaults: UserDefaults) -> Set<NotificationCategory> {
        Set(NotificationCategory.allCases.filter { isEnabled($0, in: defaults) })
    }
}

nonisolated struct NotificationPayload: Hashable, Sendable {
    let category: String
    let itemID: Int
    let url: URL?

    private static let categoryKey = "category"
    private static let itemIDKey = "itemID"
    private static let urlKey = "url"

    init(category: String, itemID: Int, url: URL?) {
        self.category = category
        self.itemID = itemID
        self.url = url
    }

    init?(userInfo: [AnyHashable: Any]) {
        guard let category = userInfo[Self.categoryKey] as? String,
              let itemID = userInfo[Self.itemIDKey] as? Int else { return nil }
        self.init(
            category: category,
            itemID: itemID,
            url: (userInfo[Self.urlKey] as? String).flatMap(URL.init(string:))
        )
    }

    var userInfo: [AnyHashable: Any] {
        var info: [AnyHashable: Any] = [Self.categoryKey: category, Self.itemIDKey: itemID]
        if let url {
            info[Self.urlKey] = url.absoluteString
        }
        return info
    }
}

struct NotificationTarget: Hashable {
    let category: NotificationCategory
    let itemID: Int
    let url: URL
}

@Observable
final class NotificationCoordinator: NSObject, UNUserNotificationCenterDelegate {
    static let ledgerKey = "zilla.notifications.ledger"
    static let authorizationRequestedKey = "zilla.notifications.authorizationRequested"
    static let markSeenAction = "mark-seen"
    static let openBrowserAction = "open-browser"

    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    @ObservationIgnored var openMainWindow: (() -> Void)?

    @ObservationIgnored private let snapshot: @MainActor () -> NotificationSnapshot?
    @ObservationIgnored private let workspace: Workspace
    @ObservationIgnored private let viewedBugs: ViewedBugsStore
    @ObservationIgnored private let viewedRevisions: ViewedRevisionsStore
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let center: UNUserNotificationCenter
    @ObservationIgnored private var started = false
    @ObservationIgnored private var observationTask: Task<Void, Never>?
    @ObservationIgnored private var activeObserver: NSObjectProtocol?
    @ObservationIgnored private var reconcileTask: Task<Void, Never>?
    @ObservationIgnored private var reconcilePending = false
    @ObservationIgnored private var mainWindowCount = 0

    init(
        snapshot: @escaping @MainActor () -> NotificationSnapshot?,
        workspace: Workspace,
        viewedBugs: ViewedBugsStore,
        viewedRevisions: ViewedRevisionsStore,
        defaults: UserDefaults = .standard,
        center: UNUserNotificationCenter = .current()
    ) {
        self.snapshot = snapshot
        self.workspace = workspace
        self.viewedBugs = viewedBugs
        self.viewedRevisions = viewedRevisions
        self.defaults = defaults
        self.center = center
        super.init()
    }

    deinit {
        observationTask?.cancel()
        if let activeObserver { NotificationCenter.default.removeObserver(activeObserver) }
    }

    func start() {
        guard !started else { return }
        started = true
        center.delegate = self
        center.setNotificationCategories(Self.categories)
        activeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { await self.refreshAuthorizationStatus() }
            }
        }
        let snapshot = self.snapshot
        observationTask = Task { [weak self] in
            await self?.refreshAuthorizationStatus()
            for await _ in Observations({ snapshot() }) {
                guard let self else { return }
                self.reconcile()
            }
        }
    }

    func mainWindowDidAppear() {
        mainWindowCount += 1
    }

    func mainWindowDidDisappear() {
        mainWindowCount = max(0, mainWindowCount - 1)
    }

    func settingsChanged() {
        reconcile()
    }

    func reconcile() {
        reconcilePending = true
        guard reconcileTask == nil else { return }
        reconcileTask = Task { [weak self] in
            await self?.drainReconciles()
        }
    }

    func refreshAuthorizationStatus() async {
        authorizationStatus = await center.notificationSettings().authorizationStatus
    }

    func requestAuthorizationIfNeeded() async {
        guard !defaults.bool(forKey: Self.authorizationRequestedKey) else { return }
        await requestAuthorization()
    }

    func requestAuthorization() async {
        defaults.set(true, forKey: Self.authorizationRequestedKey)
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
        await refreshAuthorizationStatus()
        reconcile()
    }

    private func drainReconciles() async {
        while reconcilePending {
            reconcilePending = false
            await performReconcile()
        }
        reconcileTask = nil
    }

    private func performReconcile() async {
        let delivered = Set(await center.deliveredNotifications().map(\.request.identifier))
        await refreshAuthorizationStatus()
        guard let snapshot = snapshot() else { return }
        let ledger = Self.loadLedger(from: defaults)
        let plan = NotificationPlanner.plan(
            snapshot: snapshot,
            ledger: ledger,
            delivered: delivered,
            enabled: NotificationSettings.enabledCategories(defaults),
            suppressed: suppressedIdentifiers,
            now: .now
        )
        if plan.ledger != ledger {
            Self.saveLedger(plan.ledger, to: defaults)
        }
        if !plan.remove.isEmpty {
            center.removeDeliveredNotifications(withIdentifiers: plan.remove)
        }
        guard Self.canPost(authorizationStatus) else { return }
        for candidate in plan.post {
            try? await center.add(Self.request(for: candidate))
        }
    }

    private var suppressedIdentifiers: Set<String> {
        guard NSApp.isActive, mainWindowCount > 0 else { return [] }
        return Self.identifiers(for: currentDetailRoute)
    }

    private var currentDetailRoute: DetailRoute? {
        Self.detailRoute(
            detailPath: workspace.detailPath,
            activeRevisionID: workspace.activeRevisionID,
            selectedBugID: workspace.selectedBugID,
            sidebarSelection: workspace.sidebarSelection
        )
    }

    func presentationOptions(for identifier: String) -> UNNotificationPresentationOptions {
        suppressedIdentifiers.contains(identifier) ? [] : [.banner, .list, .sound]
    }

    func handle(action: String, identifier: String, payload: NotificationPayload?) {
        guard let target = Self.target(identifier: identifier, payload: payload) else { return }
        switch action {
        case Self.markSeenAction:
            markSeen(target)
        case Self.openBrowserAction:
            NSWorkspace.shared.open(target.url)
        case UNNotificationDefaultActionIdentifier:
            open(target)
        default:
            break
        }
    }

    private func markSeen(_ target: NotificationTarget) {
        switch target.category {
        case .needinfo:
            viewedBugs.markViewed(target.itemID)
        case .review, .patch:
            viewedRevisions.markViewed(target.itemID)
        }
        reconcile()
    }

    private func open(_ target: NotificationTarget) {
        NSApp.activate()
        if mainWindowCount == 0 {
            openMainWindow?()
        } else if !NSApp.windows.contains(where: \.isVisible) {
            NSApp.windows.first(where: \.isMiniaturized)?.deminiaturize(nil)
        }
        Self.route(target, in: workspace)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let identifier = notification.request.identifier
        return await presentationOptions(for: identifier)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let request = response.notification.request
        let identifier = request.identifier
        let payload = NotificationPayload(userInfo: request.content.userInfo)
        let action = response.actionIdentifier
        await handle(action: action, identifier: identifier, payload: payload)
    }

    static var categories: Set<UNNotificationCategory> {
        let actions = [
            UNNotificationAction(identifier: markSeenAction, title: "Mark as Seen", options: []),
            UNNotificationAction(identifier: openBrowserAction, title: "Open in Browser", options: [])
        ]
        return Set(NotificationCategory.allCases.map {
            UNNotificationCategory(identifier: $0.rawValue, actions: actions, intentIdentifiers: [], options: [])
        })
    }

    static func canPost(_ status: UNAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .provisional: true
        default: false
        }
    }

    static func payload(for candidate: NotificationCandidate) -> NotificationPayload {
        NotificationPayload(category: candidate.category.rawValue, itemID: candidate.itemID, url: candidate.url)
    }

    static func request(for candidate: NotificationCandidate) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = candidate.title
        content.subtitle = candidate.subtitle
        content.body = candidate.body
        content.sound = .default
        content.threadIdentifier = candidate.category.rawValue
        content.categoryIdentifier = candidate.category.rawValue
        content.userInfo = payload(for: candidate).userInfo
        return UNNotificationRequest(identifier: candidate.identifier, content: content, trigger: nil)
    }

    static func defaultURL(for category: NotificationCategory, itemID: Int) -> URL {
        switch category {
        case .needinfo:
            URL(string: "https://bugzilla.mozilla.org/show_bug.cgi?id=\(itemID)")!
        case .review, .patch:
            URL(string: "https://phabricator.services.mozilla.com/D\(itemID)")!
        }
    }

    static func target(identifier: String, payload: NotificationPayload?) -> NotificationTarget? {
        if let payload, let category = NotificationCategory(rawValue: payload.category) {
            return NotificationTarget(
                category: category,
                itemID: payload.itemID,
                url: payload.url ?? defaultURL(for: category, itemID: payload.itemID)
            )
        }
        guard let parsed = NotificationCandidate.parse(identifier) else { return nil }
        return NotificationTarget(
            category: parsed.category,
            itemID: parsed.itemID,
            url: defaultURL(for: parsed.category, itemID: parsed.itemID)
        )
    }

    static func detailRoute(
        detailPath: [DetailRoute],
        activeRevisionID: Int?,
        selectedBugID: Int?,
        sidebarSelection: SidebarSelection?
    ) -> DetailRoute? {
        if let last = detailPath.last { return last }
        if let activeRevisionID { return .revision(activeRevisionID) }
        if sidebarSelection == .allDrafts { return nil }
        if let selectedBugID { return .bug(selectedBugID) }
        return nil
    }

    static func identifiers(for route: DetailRoute?) -> Set<String> {
        switch route {
        case .bug(let id):
            [NotificationCandidate.identifier(.needinfo, id)]
        case .revision(let id):
            [NotificationCandidate.identifier(.review, id), NotificationCandidate.identifier(.patch, id)]
        case .draft, nil:
            []
        }
    }

    static func route(_ target: NotificationTarget, in workspace: Workspace) {
        switch target.category {
        case .needinfo:
            workspace.sidebarSelection = .smart(.needsReview)
            workspace.selectedBugID = target.itemID
            workspace.activeRevisionID = nil
        case .review:
            workspace.sidebarSelection = .revisions(.reviews)
            workspace.activeRevisionID = target.itemID
        case .patch:
            workspace.sidebarSelection = .revisions(.patches)
            workspace.activeRevisionID = target.itemID
        }
        workspace.detailPath = []
    }

    static func loadLedger(from defaults: UserDefaults) -> NotificationLedger {
        guard let data = defaults.data(forKey: ledgerKey),
              let ledger = try? JSONDecoder().decode(NotificationLedger.self, from: data) else {
            return NotificationLedger()
        }
        return ledger
    }

    static func saveLedger(_ ledger: NotificationLedger, to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(ledger) else { return }
        defaults.set(data, forKey: ledgerKey)
    }
}
#endif
