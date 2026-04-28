import Foundation

public enum PhabricatorAuthentication: Sendable, Equatable {
    case none
    case apiToken(String)

    public var isAuthenticated: Bool {
        if case .none = self { return false }
        return true
    }

    var token: String? {
        if case .apiToken(let value) = self { return value }
        return nil
    }
}
