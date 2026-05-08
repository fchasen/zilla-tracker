import Foundation
import SwiftProse

enum CommentMarkdown {
    static let phabricatorProductionURL = URL(string: "https://phabricator.services.mozilla.com")!
    static let bugzillaProductionURL = URL(string: "https://bugzilla.mozilla.org")!

    static func autolinkReferences(
        in markdown: String,
        phabricatorBaseURL: URL = phabricatorProductionURL,
        bugzillaBaseURL: URL = bugzillaProductionURL
    ) -> String {
        let context = LinkContext(
            phabricator: phabricatorBaseURL.absoluteString.trimmingTrailingSlashes,
            bugzilla: bugzillaBaseURL.absoluteString.trimmingTrailingSlashes
        )
        let normalized = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var output: [String] = []
        var inFence = false
        for line in normalized.components(separatedBy: "\n") {
            if isFenceLine(line) {
                inFence.toggle()
                output.append(line)
                continue
            }
            output.append(inFence ? line : autolinkInlineReferences(in: line, context: context))
        }
        return output.joined(separator: "\n")
    }

    static func autoLinkPlugin() -> AutoLinkPlugin {
        AutoLinkPlugin(rules: [
            AutoLinkRule(
                id: "zilla.revision",
                pattern: #"(^|[^A-Za-z0-9_\/])((D)(\d+))(?=$|[\s.,;:!?\)])"#,
                linkCapture: 2,
                href: { match in
                    guard let id = match.capture(4) else { return nil }
                    return revisionURL(id: id)
                }
            ),
            AutoLinkRule(
                id: "zilla.bug-word",
                pattern: #"(^|[^A-Za-z0-9_\/])(([Bb]ug)\s+(\d+))(?=$|[\s.,;:!?\)])"#,
                linkCapture: 2,
                href: { match in
                    guard let id = match.capture(4) else { return nil }
                    return bugURL(id: id)
                }
            ),
            AutoLinkRule(
                id: "zilla.bug-hash",
                pattern: #"(^|[^A-Za-z0-9_\/])(#(\d+))(?=$|[\s.,;:!?\)])"#,
                linkCapture: 2,
                href: { match in
                    guard let id = match.capture(3) else { return nil }
                    return bugURL(id: id)
                }
            ),
        ])
    }

    static func bugURL(id: String, baseURL: URL = bugzillaProductionURL) -> String {
        "\(baseURL.absoluteString.trimmingTrailingSlashes)/show_bug.cgi?id=\(id)"
    }

    static func revisionURL(id: String, baseURL: URL = phabricatorProductionURL) -> String {
        "\(baseURL.absoluteString.trimmingTrailingSlashes)/D\(id)"
    }

    private struct LinkContext {
        let phabricator: String
        let bugzilla: String
    }

    private static func isFenceLine(_ line: String) -> Bool {
        line.firstMatch(of: #/^(\s*)(```|~~~)(.*)$/#) != nil
    }

    private static func autolinkInlineReferences(in line: String, context: LinkContext) -> String {
        let parts = line.components(separatedBy: "`")
        var rebuilt: [String] = []
        rebuilt.reserveCapacity(parts.count)
        for (index, part) in parts.enumerated() {
            rebuilt.append(index.isMultiple(of: 2) ? autolinkProse(part, context: context) : part)
        }
        return rebuilt.joined(separator: "`")
    }

    private static func autolinkProse(_ text: String, context: LinkContext) -> String {
        var protected: [String] = []
        var working = text

        working = working.replacing(#/!\[[^\]]*\]\([^)\s]+\)/#) { match in
            protect(String(match.0), in: &protected)
        }
        working = working.replacing(#/\[[^\]]+\]\([^)\s]+\)/#) { match in
            protect(String(match.0), in: &protected)
        }
        working = working.replacing(#/<([a-zA-Z][a-zA-Z0-9+.\-]*:\/\/[^>\s]+)>/#) { match in
            protect(String(match.0), in: &protected)
        }
        working = working.replacing(#/[a-zA-Z][a-zA-Z0-9+.\-]*:\/\/[^\s)\]]+/#) { match in
            protect(String(match.0), in: &protected)
        }

        working = working.replacing(#/(^|[^A-Za-z0-9_\/])(D)(\d+)(?![A-Za-z0-9_])/#) { match in
            let prefix = String(match.output.1)
            let id = String(match.output.3)
            return "\(prefix)[D\(id)](\(context.phabricator)/D\(id))"
        }
        working = working.replacing(#/(^|[^A-Za-z0-9_])([Bb]ug)\s+(\d+)(?![A-Za-z0-9_])/#) { match in
            let prefix = String(match.output.1)
            let label = String(match.output.2)
            let id = String(match.output.3)
            return "\(prefix)[\(label) \(id)](\(context.bugzilla)/show_bug.cgi?id=\(id))"
        }
        working = working.replacing(#/(^|[^A-Za-z0-9_])#(\d+)(?![A-Za-z0-9_])/#) { match in
            let prefix = String(match.output.1)
            let id = String(match.output.2)
            return "\(prefix)[#\(id)](\(context.bugzilla)/show_bug.cgi?id=\(id))"
        }

        for (index, original) in protected.enumerated() {
            working = working.replacingOccurrences(of: placeholder(index: index), with: original)
        }
        return working
    }

    private static func protect(_ value: String, in protected: inout [String]) -> String {
        let marker = placeholder(index: protected.count)
        protected.append(value)
        return marker
    }

    private static func placeholder(index: Int) -> String {
        "\u{E000}ZILLA\(index)\u{E001}"
    }
}

extension EditorController {
    func registerZillaAutoLinkPluginIfNeeded() {
        guard !plugins.contains(where: { $0.key.name == "swiftprose.autoLink" }) else { return }
        register(plugin: CommentMarkdown.autoLinkPlugin())
    }
}

private extension String {
    var trimmingTrailingSlashes: String {
        var value = self
        while value.hasSuffix("/") {
            value.removeLast()
        }
        return value
    }
}
