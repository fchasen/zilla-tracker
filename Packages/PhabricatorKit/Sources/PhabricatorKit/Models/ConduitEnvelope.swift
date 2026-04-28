import Foundation

struct ConduitEnvelope<T: Decodable>: Decodable {
    let result: T?
    let errorCode: String?
    let errorInfo: String?

    enum CodingKeys: String, CodingKey {
        case result
        case errorCode = "error_code"
        case errorInfo = "error_info"
    }
}
