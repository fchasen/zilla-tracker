import Foundation

public struct Hunk: Decodable, Sendable, Hashable {
    public let oldOffset: Int
    public let oldLen: Int
    public let newOffset: Int
    public let newLen: Int
    public let corpus: String

    public init(oldOffset: Int, oldLen: Int, newOffset: Int, newLen: Int, corpus: String) {
        self.oldOffset = oldOffset
        self.oldLen = oldLen
        self.newOffset = newOffset
        self.newLen = newLen
        self.corpus = corpus
    }

    enum CodingKeys: String, CodingKey {
        case oldOffset, oldLen, newOffset, newLen, corpus
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.oldOffset = try Self.decodeFlexibleInt(c, key: .oldOffset)
        self.oldLen = try Self.decodeFlexibleInt(c, key: .oldLen)
        self.newOffset = try Self.decodeFlexibleInt(c, key: .newOffset)
        self.newLen = try Self.decodeFlexibleInt(c, key: .newLen)
        self.corpus = try c.decodeIfPresent(String.self, forKey: .corpus) ?? ""
    }

    private static func decodeFlexibleInt(_ c: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) throws -> Int {
        if let v = try? c.decode(Int.self, forKey: key) { return v }
        if let s = try? c.decode(String.self, forKey: key), let v = Int(s) { return v }
        return 0
    }
}
