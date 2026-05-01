import Foundation

public enum UnifiedDiffParser {
    public static func parse(corpus: String, oldStart: Int, newStart: Int) -> DiffHunk {
        var lines: [DiffLine] = []
        var oldNum = oldStart
        var newNum = newStart

        for raw in splitCorpus(corpus) {
            guard let marker = raw.first else {
                lines.append(DiffLine(kind: .context, oldNumber: oldNum, newNumber: newNum, text: ""))
                oldNum += 1
                newNum += 1
                continue
            }
            let body = String(raw.dropFirst())
            switch marker {
            case " ":
                lines.append(DiffLine(kind: .context, oldNumber: oldNum, newNumber: newNum, text: body))
                oldNum += 1
                newNum += 1
            case "-":
                lines.append(DiffLine(kind: .deletion, oldNumber: oldNum, newNumber: nil, text: body))
                oldNum += 1
            case "+":
                lines.append(DiffLine(kind: .addition, oldNumber: nil, newNumber: newNum, text: body))
                newNum += 1
            case "\\":
                lines.append(DiffLine(kind: .noNewline, oldNumber: nil, newNumber: nil, text: body))
            default:
                lines.append(DiffLine(kind: .context, oldNumber: oldNum, newNumber: newNum, text: raw))
                oldNum += 1
                newNum += 1
            }
        }

        return DiffHunk(oldStart: oldStart, newStart: newStart, lines: lines)
    }

    private static func splitCorpus(_ corpus: String) -> [String] {
        if corpus.isEmpty { return [] }
        var lines = corpus.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if let last = lines.last, last.isEmpty {
            lines.removeLast()
        }
        return lines
    }
}
