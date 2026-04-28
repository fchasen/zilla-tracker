import Foundation

public enum PhabricatorError: Error, Sendable {
    case network(URLError)
    case decoding(String)
    case api(code: String, info: String)
    case unauthorized
    case invalidResponse
    case missingToken
}

extension PhabricatorError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .network(let urlError):
            return urlError.localizedDescription
        case .decoding(let detail):
            return "Could not decode Phabricator response: \(detail)"
        case .api(let code, let info):
            return "Phabricator error \(code): \(info)"
        case .unauthorized:
            return "Not authorized."
        case .invalidResponse:
            return "Invalid response from Phabricator."
        case .missingToken:
            return "No Phabricator API token configured."
        }
    }
}
