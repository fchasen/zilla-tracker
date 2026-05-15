//
//  ZillaApp.swift
//  Zilla
//
//  Created by Fred Chasen on 4/27/26.
//

import SwiftUI
import SwiftData
import BugzillaKit
import Textual

@main
struct ZillaApp: App {
    @State private var auth = AuthStore()
    @State private var phab = PhabricatorAuthStore()
    @State private var workspace = Workspace()
    @State private var viewedBugs = ViewedBugsStore()
    @State private var viewedRevisions = ViewedRevisionsStore()
    @State private var cache = ResourceCache()
    @State private var refreshScheduler: RevisionRefreshScheduler?

    private let modelContainer: ModelContainer = {
        do {
            return try ModelContainer.zillaContainer()
        } catch {
            fatalError("Failed to initialize Zilla ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .textual.blockQuoteStyle(.gitHub)
                .environment(auth)
                .environment(phab)
                .environment(workspace)
                .environment(viewedBugs)
                .environment(viewedRevisions)
                .environment(cache)
                .task {
                    workspace.cache = cache
                    auth.cacheClearHook = { [weak cache] in cache?.clear() }
                    phab.cacheClearHook = { [weak cache] in cache?.clear() }
                    await auth.bootstrap()
                    await phab.bootstrap()
                    if refreshScheduler == nil {
                        let s = RevisionRefreshScheduler(workspace: workspace, phab: phab)
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
                .environment(cache)
            }
        }
        .defaultSize(width: 1280, height: 760)
        .modelContainer(modelContainer)
        #endif
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
        let fullSchema = Schema(versionedSchema: ZillaSchemaV3.self)

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
    @Environment(AuthStore.self) private var auth
    @Environment(Workspace.self) private var workspace
    @Environment(\.scenePhase) private var scenePhase

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
    }
}
