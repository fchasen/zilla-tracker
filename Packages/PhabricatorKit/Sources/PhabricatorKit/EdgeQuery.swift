import Foundation

public enum RevisionStackEdge: Sendable, Hashable, CaseIterable {
    case parentsOfSource
    case childrenOfSource

    // Phabricator/Phorge register named conduit keys for differential edges.
    // The numeric EDGECONSTs (5, 6) are also accepted, but named keys are the
    // documented public Conduit form.
    public var conduitTypeName: String {
        switch self {
        case .parentsOfSource: return "revision.parent"
        case .childrenOfSource: return "revision.child"
        }
    }

    public static func from(conduitTypeName: String) -> RevisionStackEdge? {
        switch conduitTypeName {
        case "revision.parent", "5": return .parentsOfSource
        case "revision.child", "6": return .childrenOfSource
        default: return nil
        }
    }
}

public struct EdgeQuery: Sendable, Hashable, Encodable {
    public var sourcePHIDs: [String]
    public var types: [String]
    public var limit: Int?

    public init(sourcePHIDs: [String], types: [RevisionStackEdge], limit: Int? = 100) {
        self.sourcePHIDs = sourcePHIDs
        self.types = types.map(\.conduitTypeName)
        self.limit = limit
    }

    public init(sourcePHIDs: [String], rawTypes: [String], limit: Int? = 100) {
        self.sourcePHIDs = sourcePHIDs
        self.types = rawTypes
        self.limit = limit
    }
}

public struct Edge: Decodable, Sendable, Hashable {
    public let sourcePHID: String
    public let destinationPHID: String
    public let edgeType: String

    enum CodingKeys: String, CodingKey {
        case sourcePHID
        case destinationPHID
        case edgeType
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.sourcePHID = try c.decode(String.self, forKey: .sourcePHID)
        self.destinationPHID = try c.decode(String.self, forKey: .destinationPHID)
        if let s = try? c.decode(String.self, forKey: .edgeType) {
            self.edgeType = s
        } else if let i = try? c.decode(Int.self, forKey: .edgeType) {
            self.edgeType = String(i)
        } else {
            self.edgeType = ""
        }
    }
}

public struct EdgeSearchResult: Decodable, Sendable {
    public let data: [Edge]
    public let cursor: Cursor?

    public struct Cursor: Decodable, Sendable {
        public let limit: Int?
        public let after: String?
        public let before: String?
    }
}
