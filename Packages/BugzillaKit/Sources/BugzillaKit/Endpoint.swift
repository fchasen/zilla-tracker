import Foundation

struct Endpoint {
    enum Method: String {
        case get = "GET"
        case post = "POST"
        case put = "PUT"
        case delete = "DELETE"
    }

    var path: String
    var method: Method = .get
    var query: [URLQueryItem] = []
    var body: Data? = nil

    func url(relativeTo baseURL: URL) -> URL? {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("rest").appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )
        if !query.isEmpty {
            components?.queryItems = query
        }
        return components?.url
    }
}

extension Array where Element == URLQueryItem {
    static func repeating(_ name: String, values: [String]) -> [URLQueryItem] {
        values.map { URLQueryItem(name: name, value: $0) }
    }
}
