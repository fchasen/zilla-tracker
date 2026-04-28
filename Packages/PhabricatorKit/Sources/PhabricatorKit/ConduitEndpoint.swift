import Foundation

struct ConduitEndpoint {
    let method: String
    let body: Data

    func url(relativeTo baseURL: URL) -> URL? {
        baseURL
            .appendingPathComponent("api")
            .appendingPathComponent(method)
    }

    func request(relativeTo baseURL: URL) throws -> URLRequest {
        guard let url = url(relativeTo: baseURL) else {
            throw PhabricatorError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpShouldHandleCookies = false
        request.httpBody = body
        return request
    }
}

enum ConduitFormBody {
    static func encode(token: String?, paramsJSON: String?) -> Data {
        var pairs: [(String, String)] = []
        if let token { pairs.append(("api.token", token)) }
        if let paramsJSON, !paramsJSON.isEmpty, paramsJSON != "{}" {
            pairs.append(("params", paramsJSON))
        }
        let encoded = pairs.map { name, value in
            "\(percentEncode(name))=\(percentEncode(value))"
        }.joined(separator: "&")
        return Data(encoded.utf8)
    }

    private static let allowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()

    private static func percentEncode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
