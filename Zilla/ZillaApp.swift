//
//  ZillaApp.swift
//  Zilla
//
//  Created by Fred Chasen on 4/27/26.
//

import SwiftUI

@main
struct ZillaApp: App {
    @State private var workspace = Workspace.mock

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(workspace)
        }
    }
}
