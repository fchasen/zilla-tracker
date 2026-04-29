import Foundation
import PhabricatorKit

enum ChangesetSynthesizer {
    static func synthesize(changeset: Changeset) -> (oldContent: String, newContent: String) {
        var oldLines: [String] = []
        var newLines: [String] = []

        for hunk in changeset.hunks {
            for line in splitCorpus(hunk.corpus) {
                guard let first = line.first else {
                    oldLines.append("")
                    newLines.append("")
                    continue
                }
                let body = String(line.dropFirst())
                switch first {
                case " ":
                    oldLines.append(body)
                    newLines.append(body)
                case "-":
                    oldLines.append(body)
                case "+":
                    newLines.append(body)
                case "\\":
                    continue
                default:
                    oldLines.append(line)
                    newLines.append(line)
                }
            }
        }

        return (oldLines.joined(separator: "\n"), newLines.joined(separator: "\n"))
    }

    static func applyHunks(to oldContent: String, hunks: [Hunk]) -> String {
        var oldLines = oldContent.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if oldContent.isEmpty { oldLines = [] }
        var resultLines: [String] = []
        var oldIndex = 0

        let sortedHunks = hunks.sorted { $0.oldOffset < $1.oldOffset }

        for hunk in sortedHunks {
            let hunkOldStart = max(0, hunk.oldOffset - 1)
            while oldIndex < hunkOldStart && oldIndex < oldLines.count {
                resultLines.append(oldLines[oldIndex])
                oldIndex += 1
            }
            for line in splitCorpus(hunk.corpus) {
                guard let first = line.first else { continue }
                let body = String(line.dropFirst())
                switch first {
                case " ":
                    resultLines.append(body)
                    oldIndex += 1
                case "-":
                    oldIndex += 1
                case "+":
                    resultLines.append(body)
                case "\\":
                    continue
                default:
                    resultLines.append(line)
                }
            }
        }

        while oldIndex < oldLines.count {
            resultLines.append(oldLines[oldIndex])
            oldIndex += 1
        }

        return resultLines.joined(separator: "\n")
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
