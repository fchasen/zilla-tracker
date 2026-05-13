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

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let id = try c.decodeIfPresent(Int.self, forKey: .id) {
            self.id = id
        } else {
            self.id = 0
        }
        self.name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        self.realName = try c.decodeIfPresent(String.self, forKey: .realName)
        self.email = try c.decodeIfPresent(String.self, forKey: .email)
        self.nick = try c.decodeIfPresent(String.self, forKey: .nick)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, realName, email, nick
    }

    public var displayName: String {
        if User.isNobody(name) || User.isNobody(email) || User.isNobody(realName) { return "Nobody" }
        if let realName, !realName.isEmpty { return realName }
        if let nick, !nick.isEmpty { return nick }
        return User.localPart(of: name)
    }

    public static func displayName(for email: String?, detail: User? = nil) -> String {
        if let detail {
            return detail.displayName
        }
        guard let email, !email.isEmpty else { return "—" }
        if User.isNobody(email) { return "Nobody" }
        return User.localPart(of: email)
    }

    public static func localPart(of value: String) -> String {
        if let at = value.firstIndex(of: "@") {
            return String(value[..<at])
        }
        return value
    }

    private static func isNobody(_ value: String?) -> Bool {
        value?.lowercased().contains("nobody") == true
    }
}
