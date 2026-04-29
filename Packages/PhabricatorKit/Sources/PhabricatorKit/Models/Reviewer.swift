import Foundation

public struct Reviewer: Decodable, Sendable, Hashable, Identifiable {
    public let reviewerPHID: String
    public let status: String
    public let isBlocking: Bool
    public let actorPHID: String?

    public var id: String { reviewerPHID }

    enum CodingKeys: String, CodingKey {
        case reviewerPHID
        case status
        case isBlocking
        case actorPHID
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.reviewerPHID = try c.decode(String.self, forKey: .reviewerPHID)
        self.status = try c.decodeIfPresent(String.self, forKey: .status) ?? "added"
        if let b = try? c.decodeIfPresent(Bool.self, forKey: .isBlocking) {
            self.isBlocking = b
        } else if let i = try? c.decodeIfPresent(Int.self, forKey: .isBlocking) {
            self.isBlocking = i != 0
        } else {
            self.isBlocking = false
        }
        self.actorPHID = try c.decodeIfPresent(String.self, forKey: .actorPHID)
    }

    public init(reviewerPHID: String, status: String, isBlocking: Bool, actorPHID: String? = nil) {
        self.reviewerPHID = reviewerPHID
        self.status = status
        self.isBlocking = isBlocking
        self.actorPHID = actorPHID
    }
}

public extension Reviewer {
    enum Status {
        public static let added = "added"
        public static let accepted = "accepted"
        public static let rejected = "rejected"
        public static let blocking = "blocking"
        public static let resigned = "resigned"
        public static let acceptedPrior = "accepted-prior"
        public static let rejectedPrior = "rejected-prior"
    }
}
