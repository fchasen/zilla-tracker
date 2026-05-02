import Foundation

public enum Markdown {
    public static func toRemarkup(_ source: String) -> String {
        let normalized = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = collapseSetextHeaders(normalized.components(separatedBy: "\n"))
        var output: [String] = []
        var inFence = false
        for line in lines {
            if isFenceLine(line) {
                inFence.toggle()
                output.append(line)
                continue
            }
            if inFence {
                output.append(line)
                continue
            }
            output.append(transformLine(line))
        }
        return output.joined(separator: "\n")
    }

    static func isFenceLine(_ line: String) -> Bool {
        line.firstMatch(of: #/^(\s*)(```|~~~)(.*)$/#) != nil
    }

    static func collapseSetextHeaders(_ lines: [String]) -> [String] {
        var result: [String] = []
        var inFence = false
        var i = 0
        while i < lines.count {
            let line = lines[i]
            if isFenceLine(line) {
                inFence.toggle()
                result.append(line)
                i += 1
                continue
            }
            if inFence {
                result.append(line)
                i += 1
                continue
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let titleIsPlain = !trimmed.isEmpty
                && !trimmed.hasPrefix("#")
                && !trimmed.hasPrefix(">")
                && !trimmed.hasPrefix("-")
                && !trimmed.hasPrefix("*")
                && !trimmed.hasPrefix("+")
                && !trimmed.hasPrefix("|")
                && !trimmed.hasPrefix("=")
            if titleIsPlain, i + 1 < lines.count {
                let next = lines[i + 1].trimmingCharacters(in: .whitespaces)
                if next.count >= 3, next.allSatisfy({ $0 == "=" }) {
                    result.append("= \(trimmed) =")
                    i += 2
                    continue
                }
                if next.count >= 3, next.allSatisfy({ $0 == "-" }) {
                    result.append("== \(trimmed) ==")
                    i += 2
                    continue
                }
            }
            result.append(line)
            i += 1
        }
        return result
    }

    static func transformLine(_ line: String) -> String {
        if let header = rewriteATXHeader(line) {
            return transformInline(header)
        }
        return transformInline(line)
    }

    static func rewriteATXHeader(_ line: String) -> String? {
        guard let match = line.firstMatch(of: #/^(#{1,6})\s+(.+?)(?:\s+#+\s*)?$/#) else { return nil }
        let level = match.output.1.count
        let text = String(match.output.2).trimmingCharacters(in: .whitespaces)
        let marker = String(repeating: "=", count: level)
        return "\(marker) \(text) \(marker)"
    }

    static func transformInline(_ line: String) -> String {
        let parts = line.components(separatedBy: "`")
        guard parts.count >= 3 else { return transformProse(line) }
        var result = ""
        for (index, part) in parts.enumerated() {
            if index.isMultiple(of: 2) {
                result += transformProse(part)
            } else {
                result += "##\(part)##"
            }
        }
        return result
    }

    static func transformProse(_ text: String) -> String {
        var protected: [String] = []
        var working = text

        working = working.replacing(#/!\[([^\]]+)\]\(([^)\s]+)\)/#) { match in
            "[[\(String(match.output.2)) | \(String(match.output.1))]]"
        }

        working = working.replacing(#/\[\[[^\]]+\]\]/#) { match in
            let placeholder = makePlaceholder(index: protected.count)
            protected.append(String(match.0))
            return placeholder
        }

        working = working.replacing(#/<([a-zA-Z][a-zA-Z0-9+.\-]*:\/\/[^>\s]+)>/#) { match in
            let placeholder = makePlaceholder(index: protected.count)
            protected.append(String(match.output.1))
            return placeholder
        }

        working = working.replacing(#/[a-zA-Z][a-zA-Z0-9+.\-]*:\/\/[^\s)\]]+/#) { match in
            let placeholder = makePlaceholder(index: protected.count)
            protected.append(String(match.0))
            return placeholder
        }

        working = working.replacing(#/(^|[^_])__(?!\s|_)([^_\n]+?)__(?!_)/#) { match in
            "\(String(match.output.1))**\(String(match.output.2))**"
        }

        working = working.replacing(#/(^|[^*])\*(?!\s|\*)([^*\n]+?)\*(?!\*)/#) { match in
            "\(String(match.output.1))//\(String(match.output.2))//"
        }

        working = working.replacing(#/(^|[^A-Za-z0-9_])_(?!\s|_)([^_\n]+?)_(?![A-Za-z0-9_])/#) { match in
            "\(String(match.output.1))//\(String(match.output.2))//"
        }

        working = working.replacing(#/\[([^\]]+)\]\(([^)\s]+)\)/#) { match in
            let label = String(match.output.1)
            let url = String(match.output.2)
            return "[[\(url) | \(label)]]"
        }

        for (index, original) in protected.enumerated() {
            working = working.replacingOccurrences(of: makePlaceholder(index: index), with: original)
        }
        return working
    }

    static func makePlaceholder(index: Int) -> String {
        "\u{E000}MD\(index)\u{E001}"
    }
}
