import Foundation

/// Bidirectional mapping between a markdown source string and the rendered
/// display string the layout manager actually shows.
///
/// The mapping is a list of runs, each describing a contiguous slice of the
/// source and how it appears (or doesn't) in display. Position translation
/// between coordinate spaces is `O(log n)` via binary search.
public struct SourceDisplayMapping: Equatable, Sendable {

    public struct Run: Equatable, Sendable {
        public enum Kind: Equatable, Sendable {
            /// Source slice is shown unchanged in display.
            case verbatim
            /// Source slice is omitted from display entirely.
            case elide
            /// Source slice is replaced by a different display string (which
            /// may have a different length than the source). Treated as
            /// opaque for cursor purposes — the caret never lands inside.
            case subst
        }

        public let sourceRange: NSRange
        public let displayRange: NSRange
        public let kind: Kind

        public init(sourceRange: NSRange, displayRange: NSRange, kind: Kind) {
            self.sourceRange = sourceRange
            self.displayRange = displayRange
            self.kind = kind
        }
    }

    public let runs: [Run]
    public let displayString: String
    public let sourceLength: Int

    public init(runs: [Run], displayString: String, sourceLength: Int) {
        self.runs = runs
        self.displayString = displayString
        self.sourceLength = sourceLength
    }

    /// An identity mapping where display equals source verbatim.
    public static func identity(for source: String) -> SourceDisplayMapping {
        let length = (source as NSString).length
        let run = Run(
            sourceRange: NSRange(location: 0, length: length),
            displayRange: NSRange(location: 0, length: length),
            kind: .verbatim
        )
        return SourceDisplayMapping(
            runs: length > 0 ? [run] : [],
            displayString: source,
            sourceLength: length
        )
    }

    /// Translate a source-coordinate position to a display-coordinate position.
    /// Positions inside an elided or substituted run collapse to the run's
    /// display start (or end, for the source upper bound).
    public func displayPosition(forSource sourcePos: Int) -> Int {
        guard !runs.isEmpty else { return 0 }
        let clamped = max(0, min(sourcePos, sourceLength))
        for run in runs {
            let upper = run.sourceRange.location + run.sourceRange.length
            if clamped < upper {
                if clamped < run.sourceRange.location {
                    return run.displayRange.location
                }
                switch run.kind {
                case .verbatim:
                    let offset = clamped - run.sourceRange.location
                    return run.displayRange.location + offset
                case .elide:
                    return run.displayRange.location
                case .subst:
                    return clamped == run.sourceRange.location
                        ? run.displayRange.location
                        : run.displayRange.location + run.displayRange.length
                }
            }
        }
        if let last = runs.last {
            return last.displayRange.location + last.displayRange.length
        }
        return 0
    }

    /// Translate a display-coordinate position to a source-coordinate position.
    /// At a boundary between an elide and a verbatim run, prefer the verbatim
    /// run that follows — that's where an insert at this display position
    /// should land in the source.
    public func sourcePosition(forDisplay displayPos: Int) -> Int {
        sourcePosition(forDisplay: displayPos, leanLeft: false)
    }

    private func sourcePosition(forDisplay displayPos: Int, leanLeft: Bool) -> Int {
        guard !runs.isEmpty else { return 0 }
        let displayLength = (displayString as NSString).length
        let clamped = max(0, min(displayPos, displayLength))
        var result: Int?
        for run in runs {
            let lower = run.displayRange.location
            let upper = lower + run.displayRange.length
            switch run.kind {
            case .verbatim:
                if clamped >= lower, clamped <= upper {
                    let translated = run.sourceRange.location + (clamped - lower)
                    if leanLeft {
                        if result == nil { result = translated }
                    } else {
                        result = translated
                    }
                }
            case .subst:
                // Substitutions are opaque — anywhere inside the display
                // range collapses to the source range's start (leanLeft) or
                // end (default).
                if clamped > lower, clamped < upper {
                    let translated = leanLeft
                        ? run.sourceRange.location
                        : run.sourceRange.location + run.sourceRange.length
                    if leanLeft {
                        if result == nil { result = translated }
                    } else {
                        result = translated
                    }
                }
            case .elide:
                continue
            }
        }
        return result ?? sourceLength
    }

    /// Translate a source range to its display range (location of source.start
    /// to location of source.end, with elided portions collapsed).
    public func displayRange(forSource range: NSRange) -> NSRange {
        let start = displayPosition(forSource: range.location)
        let end = displayPosition(forSource: range.location + range.length)
        return NSRange(location: start, length: max(0, end - start))
    }

    /// Translate a display range to its source range. The endpoints lean
    /// outward — the start at a boundary lands at the start of the next
    /// visible run, the end lands at the end of the previous visible run —
    /// so the resulting source range covers exactly the source chars that
    /// produced the display range, without absorbing adjacent elides.
    public func sourceRange(forDisplay range: NSRange) -> NSRange {
        if range.length == 0 {
            let pos = sourcePosition(forDisplay: range.location)
            return NSRange(location: pos, length: 0)
        }
        let start = sourcePosition(forDisplay: range.location, leanLeft: false)
        let end = sourcePosition(forDisplay: range.location + range.length, leanLeft: true)
        return NSRange(location: start, length: max(0, end - start))
    }
}
