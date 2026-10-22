//
//  ZillaApp.swift
//  Zilla
//
//  Created by Fred Chasen on 4/27/26.
//

import SwiftUI
import SwiftData
import CoreSpotlight
import BugzillaKit
import Textual

@main
struct ZillaApp: App {
    @State private var auth: AuthStore
    @State private var phab: PhabricatorAuthStore
    @State private var workspace: Workspace
    @State private var viewedBugs: ViewedBugsStore
    @State private var viewedRevisions: ViewedRevisionsStore
    @State private var revisionActivity: RevisionActivityStore
    @State private var cache: ResourceCache
    @State private var bugIndex = BugIndexStore()
    @State private var attention: AttentionMonitor
    @State private var refreshScheduler: AttentionRefreshScheduler?
    #if os(macOS)
    @State private var notifications: NotificationCoordinator
    #endif

    private let modelContainer: ModelContainer = {
        do {
            return try ModelContainer.zillaContainer()
        } catch {
            fatalError("Failed to initialize Zilla ModelContainer: \(error)")
        }
    }()

    init() {
        let auth = AuthStore()
        let phab = PhabricatorAuthStore()
        let workspace = Workspace()
        let viewedBugs = ViewedBugsStore()
        let viewedRevisions = ViewedRevisionsStore()
        let revisionActivity = RevisionActivityStore()
        let cache = ResourceCache()
        _auth = State(initialValue: auth)
        _phab = State(initialValue: phab)
        _workspace = State(initialValue: workspace)
        _viewedBugs = State(initialValue: viewedBugs)
        _viewedRevisions = State(initialValue: viewedRevisions)
        _revisionActivity = State(initialValue: revisionActivity)
        _cache = State(initialValue: cache)
        let attention = AttentionMonitor(
            auth: auth,
            phab: phab,
            workspace: workspace,
            cache: cache,
            viewedBugs: viewedBugs,
            viewedRevisions: viewedRevisions,
            revisionActivity: revisionActivity
        )
        _attention = State(initialValue: attention)
        #if os(macOS)
        _notifications = State(initialValue: NotificationCoordinator(
            snapshot: { attention.notificationSnapshot },
            workspace: workspace,
            viewedBugs: viewedBugs,
            viewedRevisions: viewedRevisions
        ))
        #endif
    }

    var body: some Scene {
        WindowGroup(id: RootView.windowID) {
            RootView()
                .textual.blockQuoteStyle(.gitHub)
                .environment(auth)
                .environment(phab)
                .environment(workspace)
                .environment(viewedBugs)
                .environment(viewedRevisions)
                .environment(revisionActivity)
                .environment(cache)
                .environment(bugIndex)
                .environment(attention)
                #if os(macOS)
                .environment(notifications)
                #endif
                .task {
                    workspace.cache = cache
                    workspace.bugIndex = bugIndex
                    workspace.viewedBugs = viewedBugs
                    workspace.viewedRevisions = viewedRevisions
                    PendingUploadStore.shared.pruneOnce(keeping: referencedPendingUploads())
                    auth.cacheClearHook = { [weak cache] in cache?.clear() }
                    phab.cacheClearHook = { [weak cache, weak revisionActivity] in
                        cache?.clear()
                        revisionActivity?.clear()
                    }
                    await auth.bootstrap()
                    await phab.bootstrap()
                    if auth.isSignedIn {
                        Task { await bugIndex.backfill(viewedIDs: viewedBugs.ids, using: auth.client) }
                    }
                    attention.start()
                    #if os(macOS)
                    notifications.start()
                    #endif
                    if refreshScheduler == nil {
                        let s = AttentionRefreshScheduler(workspace: workspace, monitor: attention)
                        s.start()
                        refreshScheduler = s
                    }
                }
        }
        .defaultSize(width: 1600, height: 1024)
        .modelContainer(modelContainer)
        #if os(macOS)
        .commands {
            ZillaCommands(auth: auth, phab: phab, workspace: workspace, viewedBugs: viewedBugs)
        }
        #endif

        #if os(macOS)
        WindowGroup("Board", id: "component-board", for: ComponentRef.self) { component in
            if let component = component.wrappedValue {
                NavigationStack {
                    ComponentReleaseColumnBoardView(component: component)
                }
                .environment(auth)
                .environment(phab)
                .environment(workspace)
                .environment(viewedBugs)
                .environment(viewedRevisions)
                .environment(revisionActivity)
                .environment(cache)
                .environment(bugIndex)
                .environment(attention)
            }
        }
        .defaultSize(width: 1280, height: 760)
        .modelContainer(modelContainer)
        #endif
    }

    private func referencedPendingUploads() -> Set<UUID> {
        let context = modelContainer.mainContext
        let drafts = (try? context.fetch(FetchDescriptor<BugDraft>())) ?? []
        let inlineDrafts = (try? context.fetch(FetchDescriptor<InlineDraftBuffer>())) ?? []
        return Set(drafts.flatMap { PendingUploadReferences.ids(in: $0.bugDescription) })
            .union(inlineDrafts.flatMap { PendingUploadReferences.ids(in: $0.content) })
    }
}

extension ModelContainer {
    static func zillaContainer() throws -> ModelContainer {
        let syncedSchema = Schema([
            FollowedComponent.self,
            FollowedMetaBug.self,
            BugDraft.self,
            BugOrderEntry.self
        ])
        let localSchema = Schema([InlineDraftBuffer.self])
        let fullSchema = Schema(versionedSchema: ZillaSchemaV5.self)

        let cloudConfig = ModelConfiguration(
            "CloudSynced",
            schema: syncedSchema,
            cloudKitDatabase: .private("iCloud.com.fchasen.Zilla")
        )
        let localConfig = ModelConfiguration(
            "Local",
            schema: localSchema,
            cloudKitDatabase: .none
        )

        do {
            return try ModelContainer(
                for: fullSchema,
                migrationPlan: ZillaMigrationPlan.self,
                configurations: cloudConfig, localConfig
            )
        } catch {
            let localOnlyConfig = ModelConfiguration(
                "CloudSynced",
                schema: syncedSchema,
                cloudKitDatabase: .none
            )
            return try ModelContainer(
                for: fullSchema,
                migrationPlan: ZillaMigrationPlan.self,
                configurations: localOnlyConfig, localConfig
            )
        }
    }
}

struct RootView: View {
    static let windowID = "main"

    @Environment(AuthStore.self) private var auth
    @Environment(PhabricatorAuthStore.self) private var phab
    @Environment(Workspace.self) private var workspace
    @Environment(\.scenePhase) private var scenePhase
    #if os(macOS)
    @Environment(NotificationCoordinator.self) private var notifications
    @Environment(\.openWindow) private var openWindow
    #endif

    var body: some View {
        Group {
            switch auth.state {
            case .unknown:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            default:
                ContentView()
            }
        }
        .onChange(of: scenePhase) { previous, current in
            guard current == .active, previous != .active else { return }
            workspace.bugListRefreshToken = UUID()
            workspace.revisionListRefreshToken = UUID()
        }
        .onContinueUserActivity(CSSearchableItemActionType) { activity in
            guard let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
                  let bugID = BugIndexStore.bugID(from: identifier) else { return }
            workspace.selectedBugID = bugID
        }
        #if os(macOS)
        .onAppear {
            notifications.openMainWindow = { [openWindow] in openWindow(id: Self.windowID) }
            notifications.mainWindowDidAppear()
        }
        .onDisappear {
            notifications.mainWindowDidDisappear()
        }
        .task(id: auth.isSignedIn || phab.isSignedIn) {
            guard auth.isSignedIn || phab.isSignedIn else { return }
            await notifications.requestAuthorizationIfNeeded()
        }
        #endif
    }
}
