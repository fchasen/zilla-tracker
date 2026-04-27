import Foundation

public enum BugzillaError: Error, Sendable {
    case network(URLError)
    case decoding(String)
    case api(code: Int, message: String)
    case unauthorized
    case notFound
    case rateLimited(retryAfter: TimeInterval?)
    case invalidResponse
    case notImplemented
}

extension BugzillaError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .network(let urlError):
            return urlError.localizedDescription
        case .decoding(let detail):
            return "Could not decode Bugzilla response: \(detail)"
        case .api(let code, let message):
            return "Bugzilla error \(code): \(message)"
        case .unauthorized:
            return "Not authorized."
        case .notFound:
            return "Not found."
        case .rateLimited(let retryAfter):
            if let retryAfter {
                return "Rate limited. Retry after \(Int(retryAfter))s."
            }
            return "Rate limited."
        case .invalidResponse:
            return "Invalid response from Bugzilla."
        case .notImplemented:
            return "Not implemented."
        }
    }
}

struct APIErrorEnvelope: Decodable {
    let error: Bool
    let code: Int
    let message: String
}
