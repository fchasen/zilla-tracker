import Foundation

/// One source slice that should be replaced by a different display string.
/// `displayString == ""` is an elide.
public struct DisplaySubstitution: Equatable, Sendable {
    public let sourceRange: NSRange
    public let displayString: String

    public init(sourceRange: NSRange, displayString: String) {
        self.sourceRange = sourceRange
        self.displayString = displayString
    }

    public static func elide(_ range: NSRange) -> DisplaySubstitution {
        DisplaySubstitution(sourceRange: range, displayString: "")
    }
}

/// Builds a `SourceDisplayMapping` by replacing selected source ranges with
/// alternate display strings. The transform is a pure function — no parsing
/// happens here; the caller decides what to substitute based on the parse
/// trees and the current `MarginaliaMode`.
public enum DisplayTransform {
    /// Convenience for the common all-elide case.
    public static func transform(source: String, elideRanges: [NSRange]) -> SourceDisplayMapping {
        transform(source: source, substitutions: elideRanges.map(DisplaySubstitution.elide))
    }

    public static func transform(
        source: String,
        substitutions: [DisplaySubstitution]
    ) -> SourceDisplayMapping {
        let ns = source as NSString
        let total = ns.length
        guard !substitutions.isEmpty else {
            return .identity(for: source)
        }
        let normalized = normalize(substitutions, total: total)

        var runs: [SourceDisplayMapping.Run] = []
        var displayPieces: [String] = []
        var sourceCursor = 0
        var displayCursor = 0
        for sub in normalized {
            if sub.sourceRange.location > sourceCursor {
                let length = sub.sourceRange.location - sourceCursor
                let piece = ns.substring(with: NSRange(location: sourceCursor, length: length))
                runs.append(SourceDisplayMapping.Run(
                    sourceRange: NSRange(location: sourceCursor, length: length),
                    displayRange: NSRange(location: displayCursor, length: length),
                    kind: .verbatim
                ))
                displayPieces.append(piece)
                displayCursor += length
            }
            let substDisplayLength = (sub.displayString as NSString).length
            let kind: SourceDisplayMapping.Run.Kind = substDisplayLength == 0 ? .elide : .subst
            runs.append(SourceDisplayMapping.Run(
                sourceRange: sub.sourceRange,
                displayRange: NSRange(location: displayCursor, length: substDisplayLength),
                kind: kind
            ))
            if substDisplayLength > 0 {
                displayPieces.append(sub.displayString)
                displayCursor += substDisplayLength
            }
            sourceCursor = sub.sourceRange.location + sub.sourceRange.length
        }
        if sourceCursor < total {
            let length = total - sourceCursor
            let piece = ns.substring(with: NSRange(location: sourceCursor, length: length))
            runs.append(SourceDisplayMapping.Run(
                sourceRange: NSRange(location: sourceCursor, length: length),
                displayRange: NSRange(location: displayCursor, length: length),
                kind: .verbatim
            ))
            displayPieces.append(piece)
        }

        return SourceDisplayMapping(
            runs: runs,
            displayString: displayPieces.joined(),
            sourceLength: total
        )
    }

    private static func normalize(_ subs: [DisplaySubstitution], total: Int) -> [DisplaySubstitution] {
        let clamped = subs.compactMap { sub -> DisplaySubstitution? in
            let location = max(0, min(sub.sourceRange.location, total))
            let upper = min(sub.sourceRange.location + sub.sourceRange.length, total)
            let length = max(0, upper - location)
            guard length > 0 else { return nil }
            return DisplaySubstitution(
                sourceRange: NSRange(location: location, length: length),
                displayString: sub.displayString
            )
        }
        let sorted = clamped.sorted { $0.sourceRange.location < $1.sourceRange.location }
        var out: [DisplaySubstitution] = []
        for sub in sorted {
            // Strict overlap: abutting ranges (last.upper == sub.location)
            // are NOT overlapping — they represent two distinct
            // substitutions side by side.
            guard let last = out.last,
                  last.sourceRange.location + last.sourceRange.length > sub.sourceRange.location else {
                out.append(sub)
                continue
            }
            // Overlapping. Merge two elides (same operation), otherwise keep
            // the first (caller shouldn't overlap differing substitutions).
            if last.displayString.isEmpty, sub.displayString.isEmpty {
                let upper = max(
                    last.sourceRange.location + last.sourceRange.length,
                    sub.sourceRange.location + sub.sourceRange.length
                )
                out[out.count - 1] = DisplaySubstitution(
                    sourceRange: NSRange(
                        location: last.sourceRange.location,
                        length: upper - last.sourceRange.location
                    ),
                    displayString: ""
                )
            }
        }
        return out
    }
}
