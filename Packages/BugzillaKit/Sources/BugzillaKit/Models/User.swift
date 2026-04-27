import Foundation

public struct User: Codable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let name: String
    public let realName: String?
    public let email: String?
    public let nick: String?

    public init(id: Int, name: String, realName: String? = nil, email: String? = nil, nick: String? = nil) {
        self.id = id
        self.name = name
        self.realName = realName
        self.email = email
        self.nick = nick
    }
}
