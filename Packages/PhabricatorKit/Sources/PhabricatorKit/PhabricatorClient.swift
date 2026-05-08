import Foundation

public actor PhabricatorClient {
    public let baseURL: URL
    public private(set) var authentication: PhabricatorAuthentication

    let transport: Transport
    let decoder: JSONDecoder
    let encoder: JSONEncoder

    public init(
        baseURL: URL,
        authentication: PhabricatorAuthentication = .none,
        session: URLSession? = nil
    ) {
        self.baseURL = baseURL
        self.authentication = authentication
        let resolvedSession = session ?? URLSession(configuration: .ephemeral)
        self.transport = URLSessionTransport(session: resolvedSession)
        self.decoder = Self.makeDecoder()
        self.encoder = Self.makeEncoder()
    }

    init(
        baseURL: URL,
        authentication: PhabricatorAuthentication,
        transport: Transport
    ) {
        self.baseURL = baseURL
        self.authentication = authentication
        self.transport = transport
        self.decoder = Self.makeDecoder()
        self.encoder = Self.makeEncoder()
    }

    public func setAuthentication(_ authentication: PhabricatorAuthentication) {
        self.authentication = authentication
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let seconds = try? container.decode(TimeInterval.self) {
                return Date(timeIntervalSince1970: seconds)
            }
            if let raw = try? container.decode(String.self), let seconds = TimeInterval(raw) {
                return Date(timeIntervalSince1970: seconds)
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Date is neither a number nor a numeric string."
            )
        }
        return decoder
    }

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    static func wrapParams<P: Encodable>(_ params: P, token: String?, encoder: JSONEncoder) throws -> String {
        let paramsData = try encoder.encode(params)
        var dict = (try JSONSerialization.jsonObject(with: paramsData) as? [String: Any]) ?? [:]
        if let token {
            dict["__conduit__"] = ["token": token]
        }
        let mergedData = try JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys])
        return String(data: mergedData, encoding: .utf8) ?? "{}"
    }
}

extension PhabricatorClient {
    func call<P: Encodable, T: Decodable>(method: String, params: P, as type: T.Type = T.self) async throws -> T {
        let paramsJSON = try Self.wrapParams(params, token: authentication.token, encoder: encoder)
        let body = ConduitFormBody.encode(token: authentication.token, paramsJSON: paramsJSON)
        let endpoint = ConduitEndpoint(method: method, body: body)
        let request = try endpoint.request(relativeTo: baseURL)
        let (data, response) = try await transport.send(request)
        try mapStatus(response)
        let envelope: ConduitEnvelope<T>
        do {
            envelope = try decoder.decode(ConduitEnvelope<T>.self, from: data)
        } catch {
            throw PhabricatorError.decoding("\(error)")
        }
        if let code = envelope.errorCode {
            throw PhabricatorError.api(code: code, info: envelope.errorInfo ?? code)
        }
        guard let result = envelope.result else {
            throw PhabricatorError.invalidResponse
        }
        return result
    }

    private func mapStatus(_ response: HTTPURLResponse) throws {
        switch response.statusCode {
        case 200..<300:
            return
        case 401:
            throw PhabricatorError.unauthorized
        default:
            throw PhabricatorError.invalidResponse
        }
    }
}

public extension PhabricatorClient {
    func whoami() async throws -> PhabricatorUser {
        struct EmptyParams: Encodable {}
        return try await call(method: "user.whoami", params: EmptyParams())
    }

    func searchRevisions(_ query: RevisionQuery) async throws -> RevisionSearchResult {
        try await call(method: "differential.revision.search", params: query)
    }

    func searchEdges(_ query: EdgeQuery) async throws -> EdgeSearchResult {
        try await call(method: "edge.search", params: query)
    }

    func searchDiffs(_ query: DiffQuery) async throws -> DiffSearchResult {
        try await call(method: "differential.diff.search", params: query)
    }

    func getDiffs(ids: [Int]) async throws -> [DiffDetail] {
        struct Params: Encodable { let ids: [Int] }
        let raw: [String: QueryDiffsRaw] = try await call(
            method: "differential.querydiffs",
            params: Params(ids: ids)
        )
        return raw.values.map { $0.toDetail() }.sorted { $0.id > $1.id }
    }

    func searchTransactions(_ query: TransactionQuery) async throws -> TransactionSearchResult {
        try await call(method: "transaction.search", params: query)
    }

    nonisolated static func inlineComments(from transactions: [RevisionTransaction]) -> [InlineComment] {
        transactions.compactMap { $0.inlineComment() }
    }

    func editRevision(
        objectIdentifier: String,
        transactions: [RevisionEditTransaction]
    ) async throws -> RevisionEditResult {
        let params = RevisionEditRequest(objectIdentifier: objectIdentifier, transactions: transactions)
        return try await call(method: "differential.revision.edit", params: params)
    }

    func searchProjects(_ query: ProjectQuery) async throws -> ProjectSearchResult {
        try await call(method: "project.search", params: query)
    }

    func searchUsers(phids: [String]) async throws -> [PhabricatorUser] {
        guard !phids.isEmpty else { return [] }
        struct Params: Encodable { let phids: [String] }
        struct Row: Decodable, Sendable {
            let phid: String
            let userName: String
            let realName: String?
            let image: URL?
            let uri: URL?
        }
        let rows: [Row] = try await call(method: "user.query", params: Params(phids: phids))
        return rows.map { row in
            PhabricatorUser(
                phid: row.phid,
                userName: row.userName,
                realName: row.realName,
                primaryEmail: nil,
                image: row.image
            )
        }
    }

    func searchUsers(query: String, limit: Int = 12) async throws -> [PhabricatorUser] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        struct Params: Encodable {
            let constraints: Constraints
            let limit: Int

            struct Constraints: Encodable {
                let query: String
            }
        }
        struct Result: Decodable, Sendable {
            let data: [Row]
        }
        struct Row: Decodable, Sendable {
            let phid: String
            let fields: Fields

            struct Fields: Decodable, Sendable {
                let username: String
                let realName: String?
                let image: URL?
            }
        }
        let result: Result = try await call(
            method: "user.search",
            params: Params(constraints: .init(query: trimmed), limit: limit)
        )
        return result.data.map { row in
            PhabricatorUser(
                phid: row.phid,
                userName: row.fields.username,
                realName: row.fields.realName,
                primaryEmail: nil,
                image: row.fields.image
            )
        }
    }

    func getFileContent(repositoryPHID: String, commit: String, path: String) async throws -> String? {
        struct FCQ: Encodable {
            let repositoryPHID: String
            let commit: String
            let path: String
        }
        struct FCQResult: Decodable, Sendable {
            let filePHID: String?
            let tooSlow: Bool?
            let tooHuge: Bool?
        }
        let result: FCQResult
        do {
            result = try await call(
                method: "diffusion.filecontentquery",
                params: FCQ(repositoryPHID: repositoryPHID, commit: commit, path: path)
            )
        } catch let PhabricatorError.api(code, info) {
            phabricatorLog.error("filecontentquery api error: \(code) \(info) repo=\(repositoryPHID) commit=\(commit) path=\(path)")
            return nil
        } catch {
            phabricatorLog.error("filecontentquery threw: \(String(describing: error)) repo=\(repositoryPHID) commit=\(commit) path=\(path)")
            return nil
        }
        guard let phid = result.filePHID else {
            phabricatorLog.error("filecontentquery returned no filePHID (tooSlow=\(result.tooSlow ?? false), tooHuge=\(result.tooHuge ?? false)) repo=\(repositoryPHID) commit=\(commit) path=\(path)")
            return nil
        }
        do {
            let bytes = try await downloadFile(phid: phid)
            return String(data: bytes, encoding: .utf8)
        } catch {
            phabricatorLog.error("file.download failed: \(String(describing: error)) phid=\(phid)")
            return nil
        }
    }

    func downloadFile(phid: String) async throws -> Data {
        struct Params: Encodable { let phid: String }
        let base64: String = try await call(method: "file.download", params: Params(phid: phid))
        guard let data = Data(base64Encoded: base64, options: [.ignoreUnknownCharacters]) else {
            throw PhabricatorError.invalidResponse
        }
        return data
    }

    func createInlineComment(
        diffID: Int,
        path: String,
        line: Int,
        length: Int,
        isNewFile: Bool,
        content: String,
        replyToCommentPHID: String? = nil
    ) async throws -> InlineComment {
        struct Params: Encodable {
            let diffID: Int
            let filePath: String
            let lineNumber: Int
            let lineLength: Int
            let isNewFile: Bool
            let content: String
            let replyToCommentPHID: String?
        }
        let raw: DifferentialGetInlinesRaw = try await call(
            method: "differential.createinline",
            params: Params(
                diffID: diffID,
                filePath: path,
                lineNumber: line,
                lineLength: max(0, length - 1),
                isNewFile: isNewFile,
                content: content,
                replyToCommentPHID: replyToCommentPHID
            )
        )
        return raw.toModel()
    }

    func deleteDraftInline(phid: String) async throws {
        struct Params: Encodable {
            let phid: String
        }
        struct EmptyResult: Decodable, Sendable {}
        let _: EmptyResult = try await call(
            method: "differential.deleteinline",
            params: Params(phid: phid)
        )
    }
}
