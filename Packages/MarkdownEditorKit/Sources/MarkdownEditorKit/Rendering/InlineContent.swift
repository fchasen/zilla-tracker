import Foundation

public enum InlineContent: Sendable, Equatable {
    case url(URL, label: String?)
    case bugLink(id: Int, label: String)
    case userMention(handle: String, displayName: String?)
    case searchfoxLink(url: URL, label: String, symbol: String?)
    case custom(kind: String, label: String, systemImage: String)

    public var kind: String {
        switch self {
        case .url: "url"
        case .bugLink: "bugLink"
        case .userMention: "userMention"
        case .searchfoxLink: "searchfoxLink"
        case let .custom(kind, _, _): kind
        }
    }
}
