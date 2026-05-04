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

private struct OpenExternalURLKey: EnvironmentKey {
    static let defaultValue: OpenURLAction = OpenURLAction { _ in .systemAction }
}

extension EnvironmentValues {
    var openExternalURL: OpenURLAction {
        get { self[OpenExternalURLKey.self] }
        set { self[OpenExternalURLKey.self] = newValue }
    }
}

private struct MozillaLinkInterceptor: ViewModifier {
    let workspace: Workspace
    @Environment(\.openURL) private var outerOpenURL

    func body(content: Content) -> some View {
        content
            .environment(\.openExternalURL, outerOpenURL)
            .environment(\.openURL, OpenURLAction { url in
                if let id = bugzillaBugID(from: url) {
                    workspace.navigate(to: .bug(id))
                    return .handled
                }
                return .systemAction
            })
    }
}

extension View {
    func interceptingMozillaLinks(workspace: Workspace) -> some View {
        modifier(MozillaLinkInterceptor(workspace: workspace))
    }
}
