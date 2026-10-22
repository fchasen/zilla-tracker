import Foundation

public struct BugKeyword: Codable, Sendable, Hashable, Identifiable {
    public let name: String
    public let description: String

    public var id: String { name }

    public init(name: String, description: String = "") {
        self.name = name
        self.description = description
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try c.decode(String.self, forKey: .name)
        self.description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
    }
}

public struct KeywordsUpdate: Sendable, Equatable, Encodable {
    public var add: [String]?
    public var remove: [String]?
    public var set: [String]?

    public init(add: [String]? = nil, remove: [String]? = nil, set: [String]? = nil) {
        self.add = add
        self.remove = remove
        self.set = set
    }

    public static func add(_ names: [String]) -> KeywordsUpdate {
        KeywordsUpdate(add: names)
    }

    public static func remove(_ names: [String]) -> KeywordsUpdate {
        KeywordsUpdate(remove: names)
    }

    private enum CodingKeys: String, CodingKey {
        case add, remove, set
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(add, forKey: .add)
        try c.encodeIfPresent(remove, forKey: .remove)
        try c.encodeIfPresent(set, forKey: .set)
    }
}
