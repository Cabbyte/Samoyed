import Foundation
import Security

struct NestCapabilities: Codable, Sendable {
    var protocolVersion: Int
    var instanceID: String
    var auth: Auth
    struct Auth: Codable, Sendable {
        var mode: String
        var issuer: URL
        var authorizationEndpoint: URL
        var tokenEndpoint: URL
        var revocationEndpoint: URL
        var clientID: String
        var redirectURI: String
        var resource: URL
        var scopes: [String]
    }
    func validate(origin: URL) throws {
        let endpoints = [auth.authorizationEndpoint, auth.tokenEndpoint, auth.revocationEndpoint]
        for endpoint in endpoints {
            guard endpoint.scheme == "https", endpoint.host == origin.host, endpoint.port == origin.port,
                  endpoint.user == nil, endpoint.password == nil else { throw NestHTTPError.invalidServer }
        }
        guard protocolVersion == 1, auth.mode == "self-hosted", !instanceID.isEmpty,
              auth.redirectURI == "top.protium.samoyed:/oauth/callback",
              auth.issuer == origin.appendingPathComponent("api/auth"),
              auth.resource == origin.appendingPathComponent("v1"),
              Set(auth.scopes).isSubset(of: ["openid", "profile", "offline_access", "nest:sync"])
        else { throw NestHTTPError.invalidServer }
    }
}
struct NestCloudUser: Codable, Sendable {
    var id: String
    var timeZoneID: String
    var timeZoneConfirmed: Bool
}
struct NestBootstrap: Codable, Sendable {
    var user: NestCloudUser
    var entities: [NestRemoteEntity]
    var cursor: String
}
struct NestTokenResponse: Decodable, Sendable {
    var access_token: String
    var refresh_token: String?
    var expires_in: Double
    var token_type: String
}
struct NestCredentials: Codable, Sendable {
    var origin: URL
    var capabilities: NestCapabilities
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var user: NestCloudUser?
    var bindingComplete = false
    var partition: NestAccountPartition? { user.map { .init(instanceID: capabilities.instanceID, userID: $0.id) } }
}
enum NestHTTPError: LocalizedError {
    case invalidServer, loginRequired, response(Int, String), cancelled
    var errorDescription: String? {
        switch self {
        case .invalidServer: "Nest 的地址或登录配置无效。"
        case .loginRequired: "连接已失效，请重新登录。未上传的数据仍保留在此账户中。"
        case let .response(code, error): "Nest 请求失败（\(code)：\(error)）。"
        case .cancelled: "连接已取消。"
        }
    }
}

enum NestKeychain {
    private static var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "top.protium.samoyed.nest", kSecAttrAccount as String: "active-connection"] }
    static func load() throws -> NestCredentials? {
        var q = query; q[kSecReturnData as String] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw CocoaError(.fileReadNoPermission) }
        return try JSONDecoder().decode(NestCredentials.self, from: data)
    }
    static func save(_ credentials: NestCredentials) throws {
        let values: [String: Any] = [kSecValueData as String: try JSONEncoder().encode(credentials), kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            guard SecItemAdd(query.merging(values) { _, new in new } as CFDictionary, nil) == errSecSuccess else { throw CocoaError(.fileWriteNoPermission) }
        } else if status != errSecSuccess { throw CocoaError(.fileWriteNoPermission) }
    }
    static func clear() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw CocoaError(.fileWriteNoPermission) }
    }
}

/// Never forward credentials or authorization codes across an HTTP redirect.
final class NestNoRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
}

actor NestHTTPClient: NestSyncTransport {
    private var credentials: NestCredentials
    private let session: URLSession
    private var refreshTask: Task<NestTokenResponse, Error>?
    private var invalidated = false
    init(credentials: NestCredentials) {
        self.credentials = credentials
        session = URLSession(configuration: .ephemeral, delegate: NestNoRedirectDelegate(), delegateQueue: nil)
    }
    static func origin(_ text: String) throws -> URL {
        guard let c = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)), c.scheme == "https", c.host != nil, c.user == nil, c.password == nil, c.query == nil, c.fragment == nil, c.path.isEmpty || c.path == "/", let url = c.url else { throw NestHTTPError.invalidServer }
        return URL(string: url.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")))!
    }
    static func capabilities(origin: URL) async throws -> NestCapabilities {
        let session = URLSession(configuration: .ephemeral, delegate: NestNoRedirectDelegate(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let data = try await checked(session, request: URLRequest(url: origin.appendingPathComponent("v1/capabilities")))
        let c = try JSONDecoder().decode(NestCapabilities.self, from: data); try c.validate(origin: origin); return c
    }
    static func exchange(origin: URL, capabilities: NestCapabilities, code: String, verifier: String) async throws -> NestCredentials {
        let session = URLSession(configuration: .ephemeral, delegate: NestNoRedirectDelegate(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let r = form(capabilities.auth.tokenEndpoint, ["grant_type": "authorization_code", "client_id": capabilities.auth.clientID, "redirect_uri": capabilities.auth.redirectURI, "resource": capabilities.auth.resource.absoluteString, "code": code, "code_verifier": verifier])
        let t = try JSONDecoder().decode(NestTokenResponse.self, from: await checked(session, request: r))
        guard t.token_type.lowercased() == "bearer", let refresh = t.refresh_token, !refresh.isEmpty, t.expires_in > 0 else { throw NestHTTPError.invalidServer }
        return .init(origin: origin, capabilities: capabilities, accessToken: t.access_token, refreshToken: refresh, expiresAt: .now.addingTimeInterval(t.expires_in))
    }
    func identify() async throws -> NestCloudUser {
        struct Identity: Decodable { var user: NestCloudUser }
        let user = try JSONDecoder().decode(Identity.self, from: await request("v1/identity")).user
        if let previous = credentials.user, previous.id != user.id { throw NestHTTPError.invalidServer }
        credentials.user = user; try persist(); return user
    }
    func snapshot() -> NestCredentials { credentials }
    func completeBinding() throws { credentials.bindingComplete = true; try persist() }
    func invalidate() { invalidated = true; refreshTask?.cancel(); session.invalidateAndCancel() }
    func setTimeZone(_ zone: String, expected: String) async throws -> NestCloudUser {
        let data = try JSONEncoder().encode(["timeZoneID": NestJSON.string(zone), "expectedTimeZoneID": .string(expected), "confirmed": .bool(true)])
        let user = try JSONDecoder().decode(NestCloudUser.self, from: await request("v1/account/time-zone", method: "POST", body: data))
        credentials.user = user; try persist(); return user
    }
    func bootstrap() async throws -> NestBootstrap { try JSONDecoder().decode(NestBootstrap.self, from: await request("v1/sync/bootstrap")) }
    func scheduleCache() async throws -> NestScheduleCache { try JSONDecoder().decode(NestScheduleCache.self, from: await request("v1/schedule-cache")) }
    func push(_ operations: [NestSyncCommand]) async throws -> [NestPushResult] {
        struct Body: Encodable { var operations: [NestSyncCommand] }
        struct Response: Decodable { var results: [NestPushResult] }
        return try JSONDecoder().decode(Response.self, from: await request("v1/sync/push", method: "POST", body: JSONEncoder().encode(Body(operations: operations)))).results
    }
    func pull(cursor: String) async throws -> NestPullPage {
        try JSONDecoder().decode(NestPullPage.self, from: await request("v1/sync/pull", query: [URLQueryItem(name: "cursor", value: cursor)]))
    }
    func resolve(_ day: LocalDay) async throws {
        _ = try await request("v1/plans/resolve", method: "POST", body: JSONEncoder().encode(day))
    }
    func request(_ path: String, method: String = "GET", body: Data? = nil, query: [URLQueryItem] = []) async throws -> Data {
        guard !invalidated else { throw NestHTTPError.cancelled }
        if credentials.expiresAt.timeIntervalSinceNow < 30 { try await refresh() }
        var url = URLComponents(url: credentials.origin.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { url.queryItems = query }
        var req = URLRequest(url: url.url!); req.httpMethod = method; req.httpBody = body
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        do { return try await Self.checked(session, request: req) }
        catch NestHTTPError.loginRequired {
            try await refresh()
            req.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
            return try await Self.checked(session, request: req)
        }
    }
    func refresh() async throws {
        guard !invalidated else { throw NestHTTPError.cancelled }
        if let refreshTask { try install(await refreshTask.value); return }
        let c = credentials, session = session
        let task = Task {
            let req = Self.form(c.capabilities.auth.tokenEndpoint, ["grant_type": "refresh_token", "client_id": c.capabilities.auth.clientID, "refresh_token": c.refreshToken, "resource": c.capabilities.auth.resource.absoluteString])
            return try JSONDecoder().decode(NestTokenResponse.self, from: await Self.checked(session, request: req))
        }
        refreshTask = task; defer { refreshTask = nil }
        try install(await task.value)
    }
    private func install(_ t: NestTokenResponse) throws {
        guard !invalidated, t.token_type.lowercased() == "bearer", t.expires_in > 0 else { throw NestHTTPError.loginRequired }
        credentials.accessToken = t.access_token; credentials.refreshToken = t.refresh_token ?? credentials.refreshToken; credentials.expiresAt = .now.addingTimeInterval(t.expires_in)
        try persist()
    }
    private func persist() throws { guard !invalidated else { throw NestHTTPError.cancelled }; try NestKeychain.save(credentials) }
    private static func form(_ url: URL, _ values: [String: String]) -> URLRequest {
        var components = URLComponents(); components.queryItems = values.map { .init(name: $0.key, value: $0.value) }
        var r = URLRequest(url: url); r.httpMethod = "POST"; r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        r.httpBody = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B").data(using: .utf8); return r
    }
    private static func checked(_ session: URLSession, request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw NestHTTPError.invalidServer }
        if response.statusCode == 401 { throw NestHTTPError.loginRequired }
        guard (200..<300).contains(response.statusCode) else {
            struct Failure: Decodable { var error: String? }
            throw NestHTTPError.response(response.statusCode, (try? JSONDecoder().decode(Failure.self, from: data).error) ?? "request_failed")
        }
        return data
    }
}
