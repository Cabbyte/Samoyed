import Foundation

public enum NestJSON: Codable, Equatable, Sendable {
    case object([String: NestJSON]), array([NestJSON]), string(String), number(Double), bool(Bool), null
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode([NestJSON].self) { self = .array(v) }
        else { self = .object(try c.decode([String: NestJSON].self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case let .bool(v): try c.encode(v)
        case let .string(v): try c.encode(v)
        case let .number(v): try c.encode(v)
        case let .array(v): try c.encode(v)
        case let .object(v): try c.encode(v)
        }
    }
}

struct NestRemoteEntity: Codable, Equatable, Sendable {
    var kind: String
    var id: String
    var revision: Int
    var deleted: Bool
    var body: NestJSON
}
struct NestScheduleCache: Codable, Sendable {
    var cursor: String
    var timeZoneID: String
    var versions: [NestRemoteEntity]
}
struct NestPullPage: Codable, Sendable { var cursor: String; var hasMore: Bool; var changes: [NestRemoteEntity] }
struct NestSyncCommand: Codable, Sendable {
    var operationID: String; var kind: String; var entityID: String; var expectedRevision: Int; var deleted: Bool; var payload: NestJSON
    init(_ op: NestOutboxOperation) throws {
        operationID = op.operationID; kind = op.kind; entityID = op.entityID; expectedRevision = op.expectedRevision; deleted = op.deleted
        payload = try JSONDecoder().decode(NestJSON.self, from: op.payload)
    }
}
struct NestPushResult: Codable, Sendable {
    var operationID: String
    var status: String
    var revision: Int?
    var body: NestJSON?
    var deleted: Bool?
    var error: String?
    var details: Details?
    struct Details: Codable, Sendable { var remote: NestRemoteEntity? }
}

/// An instance and user together identify local data. Names and emails never participate.
struct NestAccountPartition: Codable, Equatable, Sendable {
    let instanceID: String
    let userID: String
    var key: String { "nest:" + Data(instanceID.utf8).base64EncodedString() + ":" + Data(userID.utf8).base64EncodedString() }
}

protocol NestSyncTransport: Sendable {
    func push(_ operations: [NestSyncCommand]) async throws -> [NestPushResult]
    func pull(cursor: String) async throws -> NestPullPage
}

actor NestURLSessionTransport: NestSyncTransport {
    let origin: URL
    let accessToken: String
    private let session = URLSession(configuration: .ephemeral)
    init(origin: URL, accessToken: String) throws {
        guard origin.scheme == "https", origin.host != nil, origin.user == nil, origin.password == nil else { throw CocoaError(.coderInvalidValue) }
        self.origin = origin; self.accessToken = accessToken
    }
    func push(_ operations: [NestSyncCommand]) async throws -> [NestPushResult] {
        struct Body: Encodable { var operations: [NestSyncCommand] }
        struct Response: Decodable { var results: [NestPushResult] }
        var request = URLRequest(url: origin.appendingPathComponent("v1/sync/push"))
        request.httpMethod = "POST"; request.httpBody = try JSONEncoder().encode(Body(operations: operations))
        return try await send(request, as: Response.self).results
    }
    func pull(cursor: String) async throws -> NestPullPage {
        var url = URLComponents(url: origin.appendingPathComponent("v1/sync/pull"), resolvingAgainstBaseURL: false)!
        url.queryItems = [URLQueryItem(name: "cursor", value: cursor)]
        return try await send(URLRequest(url: url.url!), as: NestPullPage.self)
    }
    private func send<T: Decodable>(_ request: URLRequest, as: T.Type) async throws -> T {
        var request = request
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else { throw URLError(.userAuthenticationRequired) }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
