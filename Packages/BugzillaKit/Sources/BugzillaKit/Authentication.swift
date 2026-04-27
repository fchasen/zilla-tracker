import Foundation

public enum Authentication: Sendable, Equatable {
    case none
    case apiKey(String)
    case token(String, userID: Int)

    var isAuthenticated: Bool {
        if case .none = self { return false }
        return true
    }

    func apply(to request: inout URLRequest) {
        switch self {
        case .none:
            return
        case .apiKey(let key):
            request.setValue(key, forHTTPHeaderField: "X-BUGZILLA-API-KEY")
        case .token(let token, _):
            request.setValue(token, forHTTPHeaderField: "X-BUGZILLA-TOKEN")
        }
    }
}
