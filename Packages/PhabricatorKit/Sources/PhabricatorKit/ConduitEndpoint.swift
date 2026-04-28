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
        request.httpBody = body
        return request
    }
}

enum ConduitFormBody {
    static func encode(paramsJSON: String?) -> Data {
        guard let paramsJSON, !paramsJSON.isEmpty, paramsJSON != "{}" else {
            return Data()
        }
        let encoded = "params=\(percentEncode(paramsJSON))"
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
