import Foundation

public enum Remarkup {
    public static let phabricatorProductionURL = URL(string: "https://phabricator.services.mozilla.com")!
    public static let bugzillaProductionURL = URL(string: "https://bugzilla.mozilla.org")!

    public static func toCommonMark(
        _ source: String,
        phabricatorBaseURL: URL = phabricatorProductionURL,
        bugzillaBaseURL: URL = bugzillaProductionURL
    ) -> String {
        let context = Context(
            phabricator: phabricatorBaseURL.absoluteString.trimmingTrailingSlashes,
            bugzilla: bugzillaBaseURL.absoluteString.trimmingTrailingSlashes
        )
        let normalized = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = rewriteOrderedLists(normalized.components(separatedBy: "\n"))
        var output: [String] = []
        var inFence = false
        for line in lines {
            if let fence = parseFenceLine(line) {
                if !inFence {
                    inFence = true
                    output.append(fence.rewritten)
                } else {
                    inFence = false
                    output.append(fence.rewritten)
                }
                continue
            }
            if inFence {
                output.append(line)
                continue
            }
            output.append(transformLine(line, context: context))
        }
        return output.joined(separator: "\n")
    }

    struct Context {
        let phabricator: String
        let bugzilla: String
    }

    struct FenceInfo {
        let rewritten: String
    }

    static func rewriteOrderedLists(_ lines: [String]) -> [String] {
        var result: [String] = []
        var inFence = false
        var counter = 0
        var lastIndent: String? = nil

        func isHashListLine(_ line: String) -> Bool {
            line.firstMatch(of: #/^\s*#\s+\S/#) != nil
        }

        for (idx, line) in lines.enumerated() {
            if parseFenceLine(line) != nil {
                inFence.toggle()
                counter = 0
                lastIndent = nil
                result.append(line)
                continue
            }
            if inFence {
                result.append(line)
                continue
            }
            guard let match = line.firstMatch(of: #/^(\s*)#\s+(.+)$/#) else {
                counter = 0
                lastIndent = nil
                result.append(line)
                continue
            }
            let leading = String(match.output.1)
            let body = String(match.output.2)
            let prevIsHash = idx > 0 && isHashListLine(lines[idx - 1])
            let nextIsHash = idx + 1 < lines.count && isHashListLine(lines[idx + 1])
            if prevIsHash || nextIsHash {
                if lastIndent != leading { counter = 0 }
                counter += 1
                lastIndent = leading
                result.append("\(leading)\(counter). \(body)")
            } else {
                counter = 0
                lastIndent = nil
                result.append(line)
            }
        }
        return result
    }

    static func parseFenceLine(_ line: String) -> FenceInfo? {
        guard let match = line.firstMatch(of: #/^(\s*)(```|~~~)(.*)$/#) else { return nil }
        let leading = String(match.output.1)
        let fence = String(match.output.2)
        let info = String(match.output.3).trimmingCharacters(in: .whitespaces)
        let lang: String
        if info.isEmpty {
            lang = ""
        } else if let langMatch = info.firstMatch(of: #/\blang\s*=\s*([A-Za-z0-9_+\-.#]+)/#) {
            lang = String(langMatch.output.1)
        } else if info.contains("=") {
            lang = ""
        } else {
            lang = info
        }
        return FenceInfo(rewritten: leading + fence + lang)
    }

    static func transformLine(_ line: String, context: Context) -> String {
        if let header = rewriteHeader(line) {
            return transformInline(header, context: context)
        }
        if let callout = rewriteCallout(line) {
            return transformInline(callout, context: context)
        }
        return transformInline(line, context: context)
    }

    static func rewriteHeader(_ line: String) -> String? {
        guard let match = line.firstMatch(of: #/^(=+)\s+(.+?)(?:\s+=+\s*)?$/#) else { return nil }
        let level = min(match.output.1.count, 6)
        let text = String(match.output.2).trimmingCharacters(in: .whitespaces)
        return String(repeating: "#", count: level) + " " + text
    }

    static func rewriteCallout(_ line: String) -> String? {
        guard let match = line.firstMatch(of: #/^(NOTE|WARNING|IMPORTANT):\s*(.*)$/#) else { return nil }
        let label: String
        switch String(match.output.1) {
        case "NOTE": label = "Note"
        case "WARNING": label = "Warning"
        case "IMPORTANT": label = "Important"
        default: label = String(match.output.1)
        }
        let body = String(match.output.2)
        return "> **\(label):** " + body
    }

    static func transformInline(_ line: String, context: Context) -> String {
        let parts = line.components(separatedBy: "`")
        var rebuilt: [String] = []
        for (index, part) in parts.enumerated() {
            if index.isMultiple(of: 2) {
                rebuilt.append(transformProse(part, context: context))
            } else {
                rebuilt.append(part)
            }
        }
        return rebuilt.joined(separator: "`")
    }

    static func transformProse(_ text: String, context: Context) -> String {
        var protected: [String] = []
        var working = text

        working = working.replacing(#/\[\[\s*([^\]|]+?)\s*(?:\|\s*([^\]]+?)\s*)?\]\]/#) { match in
            let target = String(match.output.1)
            let name = match.output.2.map(String.init)
            return resolveBracketLink(target: target, name: name, context: context)
        }

        working = working.replacing(#/\[([^\]]+)\]\(([^)\s]+)\)/#) { match in
            let placeholder = makePlaceholder(index: protected.count)
            protected.append(String(match.0))
            return placeholder
        }
        working = working.replacing(#/<([a-zA-Z][a-zA-Z0-9+.\-]*:\/\/[^>\s]+)>/#) { match in
            let placeholder = makePlaceholder(index: protected.count)
            protected.append(String(match.0))
            return placeholder
        }
        working = working.replacing(#/[a-zA-Z][a-zA-Z0-9+.\-]*:\/\/[^\s)\]]+/#) { match in
            let placeholder = makePlaceholder(index: protected.count)
            protected.append(String(match.0))
            return placeholder
        }

        working = working.replacing(#/##(?!\s)([^#\n]+?)##/#) { match in
            "`\(String(match.output.1))`"
        }
        working = working.replacing(#/(^|[^A-Za-z0-9:])\/\/(?!\s)([^\/\n]+?)\/\//#) { match in
            "\(String(match.output.1))*\(String(match.output.2))*"
        }
        working = working.replacing(#/(^|[^_])__(?!_)([^_\n]+?)__(?!_)/#) { match in
            "\(String(match.output.1))<u>\(String(match.output.2))</u>"
        }
        working = working.replacing(#/!!(?!\s)([^!\n]+?)!!/#) { match in
            "**\(String(match.output.1))**"
        }

        working = working.replacing(#/\{(T|D|F)(\d+)\}/#) { match in
            let kind = String(match.output.1)
            let id = String(match.output.2)
            return "[\(kind)\(id)](\(context.phabricator)/\(kind)\(id))"
        }
        working = working.replacing(#/(^|[^A-Za-z0-9_\/])(T|D)(\d+)(#\d+)?(?![A-Za-z0-9_])/#) { match in
            let prefix = String(match.output.1)
            let kind = String(match.output.2)
            let id = String(match.output.3)
            let anchor = match.output.4.map(String.init) ?? ""
            return "\(prefix)[\(kind)\(id)\(anchor)](\(context.phabricator)/\(kind)\(id)\(anchor))"
        }
        working = working.replacing(#/(^|[^A-Za-z0-9_\/])r([A-Z]+)([a-f0-9]{7,}|\d+)(?![A-Za-z0-9_])/#) { match in
            let prefix = String(match.output.1)
            let callsign = String(match.output.2)
            let id = String(match.output.3)
            return "\(prefix)[r\(callsign)\(id)](\(context.phabricator)/r\(callsign)\(id))"
        }
        working = working.replacing(#/(^|[^A-Za-z0-9_])@([A-Za-z0-9_][A-Za-z0-9_.\-]*)/#) { match in
            let prefix = String(match.output.1)
            let raw = String(match.output.2)
            let name = raw.trimmingTrailingPunctuation
            let suffix = String(raw.dropFirst(name.count))
            return "\(prefix)[@\(name)](\(context.phabricator)/p/\(name)/)" + suffix
        }
        working = working.replacing(#/(^|[^A-Za-z0-9_])([Bb]ug)\s+(\d+)/#) { match in
            let prefix = String(match.output.1)
            let label = String(match.output.2)
            let id = String(match.output.3)
            return "\(prefix)[\(label) \(id)](\(context.bugzilla)/show_bug.cgi?id=\(id))"
        }

        for (index, original) in protected.enumerated() {
            working = working.replacingOccurrences(of: makePlaceholder(index: index), with: original)
        }
        return working
    }

    static func resolveBracketLink(target: String, name: String?, context: Context) -> String {
        let url: String
        if target.firstMatch(of: #/^[a-zA-Z][a-zA-Z0-9+.\-]*:\/\//#) != nil {
            url = target
        } else if target.hasPrefix("/") {
            url = context.phabricator + target
        } else {
            let encoded = target.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? target
            url = "\(context.phabricator)/w/\(encoded)"
        }
        let display: String
        if let name, !name.isEmpty {
            display = name
        } else {
            display = target
        }
        return "[\(display)](\(url))"
    }

    static func makePlaceholder(index: Int) -> String {
        "\u{E000}REMARKUP\(index)\u{E001}"
    }
}

private extension String {
    var trimmingTrailingSlashes: String {
        var s = self
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }

    var trimmingTrailingPunctuation: String {
        var s = self
        while let last = s.last, ".,;:!?".contains(last) { s.removeLast() }
        return s
    }
}
