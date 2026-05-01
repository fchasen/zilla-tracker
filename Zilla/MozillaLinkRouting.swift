import SwiftUI

func bugzillaBugID(from url: URL) -> Int? {
    guard url.host == "bugzilla.mozilla.org" else { return nil }

    if url.path == "/show_bug.cgi" {
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if let raw = comps?.queryItems?.first(where: { $0.name == "id" })?.value,
           let id = Int(raw) {
            return id
        }
    }

    let trimmed = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    if !trimmed.isEmpty, !trimmed.contains("/"), let id = Int(trimmed) {
        return id
    }

    return nil
}

extension View {
    func interceptingMozillaLinks(workspace: Workspace) -> some View {
        environment(\.openURL, OpenURLAction { url in
            if let id = bugzillaBugID(from: url) {
                workspace.navigate(to: .bug(id))
                return .handled
            }
            return .systemAction
        })
    }
}
