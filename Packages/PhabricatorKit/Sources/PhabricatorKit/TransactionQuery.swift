import Foundation

public struct TransactionQuery: Sendable, Hashable, Encodable {
    public var objectIdentifier: String
    public var limit: Int?
    public var before: String?
    public var after: String?

    public init(objectIdentifier: String, limit: Int? = 100, before: String? = nil, after: String? = nil) {
        self.objectIdentifier = objectIdentifier
        self.limit = limit
        self.before = before
        self.after = after
    }
}
