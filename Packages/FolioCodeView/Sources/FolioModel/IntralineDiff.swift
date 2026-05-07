import Foundation

public enum IntralineDiff {
    public struct Result: Sendable, Hashable {
        public let oldRanges: [NSRange]
        public let newRanges: [NSRange]

        public init(oldRanges: [NSRange], newRanges: [NSRange]) {
            self.oldRanges = oldRanges
            self.newRanges = newRanges
        }

        public var isEmpty: Bool { oldRanges.isEmpty && newRanges.isEmpty }
    }

    public static func compute(old: String, new: String) -> Result {
        if old == new {
            return Result(oldRanges: [], newRanges: [])
        }
        let oldTokens = tokenize(old)
        let newTokens = tokenize(new)
        let oldKeys = oldTokens.map(\.text)
        let newKeys = newTokens.map(\.text)
        if oldKeys == newKeys {
            return Result(oldRanges: [], newRanges: [])
        }
        let diff = newKeys.difference(from: oldKeys)
        var oldRaw: [NSRange] = []
        var newRaw: [NSRange] = []
        for change in diff {
            switch change {
            case let .remove(offset, _, _):
                let tok = oldTokens[offset]
                oldRaw.append(NSRange(location: tok.location, length: tok.length))
            case let .insert(offset, _, _):
                let tok = newTokens[offset]
                newRaw.append(NSRange(location: tok.location, length: tok.length))
            }
        }
        return Result(
            oldRanges: mergeAdjacent(oldRaw.sorted { $0.location < $1.location }),
            newRanges: mergeAdjacent(newRaw.sorted { $0.location < $1.location })
        )
    }

    private struct Token {
        let text: String
        let location: Int
        let length: Int
    }

    private static func tokenize(_ s: String) -> [Token] {
        let nsString = s as NSString
        var tokens: [Token] = []
        var i = 0
        let count = nsString.length
        while i < count {
            let start = i
            let u = nsString.character(at: i)
            if isWordUnit(u) {
                while i < count, isWordUnit(nsString.character(at: i)) { i += 1 }
            } else if isWhitespaceUnit(u) {
                while i < count, isWhitespaceUnit(nsString.character(at: i)) { i += 1 }
            } else {
                i += 1
            }
            let text = nsString.substring(with: NSRange(location: start, length: i - start))
            tokens.append(Token(text: text, location: start, length: i - start))
        }
        return tokens
    }

    private static func isWordUnit(_ u: UInt16) -> Bool {
        if u >= 0x30 && u <= 0x39 { return true }
        if u >= 0x41 && u <= 0x5A { return true }
        if u >= 0x61 && u <= 0x7A { return true }
        if u == 0x5F { return true }
        return u >= 0x80
    }

    private static func isWhitespaceUnit(_ u: UInt16) -> Bool {
        u == 0x20 || u == 0x09
    }

    private static func mergeAdjacent(_ ranges: [NSRange]) -> [NSRange] {
        var merged: [NSRange] = []
        for r in ranges {
            if let last = merged.last, last.location + last.length == r.location {
                merged[merged.count - 1] = NSRange(
                    location: last.location,
                    length: last.length + r.length
                )
            } else {
                merged.append(r)
            }
        }
        return merged
    }
}
