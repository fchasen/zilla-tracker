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
        let oldUnits = Array(old.utf16)
        let newUnits = Array(new.utf16)
        if oldUnits == newUnits {
            return Result(oldRanges: [], newRanges: [])
        }
        let diff = newUnits.difference(from: oldUnits)
        var oldOffsets: [Int] = []
        var newOffsets: [Int] = []
        for change in diff {
            switch change {
            case .remove(let offset, _, _):
                oldOffsets.append(offset)
            case .insert(let offset, _, _):
                newOffsets.append(offset)
            }
        }
        return Result(
            oldRanges: groupIntoRanges(oldOffsets.sorted()),
            newRanges: groupIntoRanges(newOffsets.sorted())
        )
    }

    private static func groupIntoRanges(_ offsets: [Int]) -> [NSRange] {
        var result: [NSRange] = []
        var i = 0
        while i < offsets.count {
            let start = offsets[i]
            var end = start
            while i + 1 < offsets.count && offsets[i + 1] == end + 1 {
                end += 1
                i += 1
            }
            result.append(NSRange(location: start, length: end - start + 1))
            i += 1
        }
        return result
    }
}
