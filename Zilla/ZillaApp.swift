//
//  ZillaApp.swift
//  Zilla
//
//  Created by Fred Chasen on 4/27/26.
//

import SwiftUI
import SwiftData

@main
struct ZillaApp: App {
    @State private var auth = AuthStore()
    @State private var phab = PhabricatorAuthStore()
    @State private var workspace = Workspace()
    @State private var viewedBugs = ViewedBugsStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(auth)
                .environment(phab)
                .environment(workspace)
                .environment(viewedBugs)
                .task {
                    await auth.bootstrap()
                    await phab.bootstrap()
                }
        }
        .defaultSize(width: 1600, height: 1024)
        .modelContainer(for: [FollowedComponent.self, FollowedMetaBug.self, BugDraft.self])
    }
}

struct RootView: View {
    @Environment(AuthStore.self) private var auth

    var body: some View {
        switch auth.state {
        case .unknown:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .signedIn:
            ContentView()
        case .signedOut, .signingIn, .error:
            SignInView()
        }
    }
}
