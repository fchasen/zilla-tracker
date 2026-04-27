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
    @State private var workspace = Workspace()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(auth)
                .environment(workspace)
                .task { await auth.bootstrap() }
        }
        .modelContainer(for: [FollowedComponent.self, FollowedMetaBug.self])
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
