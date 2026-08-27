import Foundation

enum DraftConsumption {
    /// What should stay in a composer after `submitted` was posted from it.
    ///
    /// `submitted` must be the raw, untrimmed draft value snapshotted *before*
    /// the network call — the composer keeps accepting input during the round
    /// trip, so the value on return is not necessarily the one that was sent.
    /// Returns `nil` when the draft can be cleared. Anything that does not
    /// cleanly extend `submitted` is returned untouched rather than discarded;
    /// the rich editor re-serializes the whole document on every edit, so a
    /// mid-document change can rewrite text ahead of the insertion point.
    static func remainder(after submitted: String, in current: String) -> String? {
        if current == submitted { return nil }
        guard current.hasPrefix(submitted) else { return current }
        let suffix = current.dropFirst(submitted.count)
        let trimmed = suffix.drop { $0.isWhitespace || $0.isNewline }
        return trimmed.isEmpty ? nil : String(trimmed)
    }
}
