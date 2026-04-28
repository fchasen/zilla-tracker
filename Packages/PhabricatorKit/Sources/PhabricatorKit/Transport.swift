import Foundation
import os

protocol Transport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct URLSessionTransport: Transport {
    let session: URLSession

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw PhabricatorError.invalidResponse
            }
            return (data, http)
        } catch let urlError as URLError {
            throw PhabricatorError.network(urlError)
        }
    }
}

let phabricatorLog = Logger(subsystem: "com.zilla.phabricator", category: "PhabricatorKit")
