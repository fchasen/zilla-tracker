import Foundation

public struct RevisionStatus: Codable, Sendable, Hashable {
    public let value: String
    public let name: String
    public let closed: Bool
    public let color: String?

    public init(value: String, name: String, closed: Bool, color: String? = nil) {
        self.value = value
        self.name = name
        self.closed = closed
        self.color = color
    }

    enum CodingKeys: String, CodingKey {
        case value, name, closed
        case color = "color.ansi"
    }

    public var isOpen: Bool { !closed }
}

public extension RevisionStatus {
    enum Value {
        public static let draft = "draft"
        public static let needsReview = "needs-review"
        public static let needsRevision = "needs-revision"
        public static let accepted = "accepted"
        public static let changesPlanned = "changes-planned"
        public static let published = "published"
        public static let abandoned = "abandoned"

        public static let openValues: [String] = [
            draft, needsReview, needsRevision, accepted, changesPlanned
        ]
    }
}
