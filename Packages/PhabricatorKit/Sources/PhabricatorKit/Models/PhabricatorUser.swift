import Foundation

public struct PhabricatorUser: Decodable, Sendable, Hashable, Identifiable {
    public let phid: String
    public let userName: String
    public let realName: String?
    public let primaryEmail: String?
    public let image: URL?

    public var id: String { phid }
}
