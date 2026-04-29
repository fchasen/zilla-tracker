import Foundation

public enum RevisionAction: String, Sendable, Hashable, CaseIterable {
    case comment
    case accept
    case reject
    case resign
    case abandon
    case reclaim
    case reopen
    case close
    case planChanges = "plan-changes"
    case requestReview = "request-review"
}

public struct RevisionEditTransaction: Sendable, Hashable, Encodable {
    public let type: String
    public let value: Value

    public enum Value: Sendable, Hashable, Encodable {
        case bool(Bool)
        case string(String)

        public func encode(to encoder: Encoder) throws {
            var c = encoder.singleValueContainer()
            switch self {
            case .bool(let v): try c.encode(v)
            case .string(let v): try c.encode(v)
            }
        }
    }

    public init(type: String, value: Value) {
        self.type = type
        self.value = value
    }

    public static func action(_ action: RevisionAction) -> RevisionEditTransaction {
        RevisionEditTransaction(type: action.rawValue, value: .bool(true))
    }

    public static func comment(_ body: String) -> RevisionEditTransaction {
        RevisionEditTransaction(type: RevisionAction.comment.rawValue, value: .string(body))
    }
}

public struct RevisionEditRequest: Sendable, Hashable, Encodable {
    public let objectIdentifier: String
    public let transactions: [RevisionEditTransaction]

    public init(objectIdentifier: String, transactions: [RevisionEditTransaction]) {
        self.objectIdentifier = objectIdentifier
        self.transactions = transactions
    }
}

public struct RevisionEditResult: Decodable, Sendable {
    public let object: ObjectRef?
    public let transactions: [TransactionRef]?

    public struct ObjectRef: Decodable, Sendable {
        public let id: Int
        public let phid: String

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            if let i = try? c.decode(Int.self, forKey: .id) { self.id = i }
            else if let s = try? c.decode(String.self, forKey: .id), let i = Int(s) { self.id = i }
            else { self.id = 0 }
            self.phid = try c.decode(String.self, forKey: .phid)
        }

        enum CodingKeys: String, CodingKey { case id, phid }
    }

    public struct TransactionRef: Decodable, Sendable {
        public let phid: String
    }
}
