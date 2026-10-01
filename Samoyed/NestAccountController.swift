import Foundation
import Observation
import AuthenticationServices
import CryptoKit
import UIKit

@MainActor @Observable
final class NestAccountController: NSObject, ASWebAuthenticationPresentationContextProviding {
    private(set) var origin: URL?
    private(set) var user: NestCloudUser?
    private(set) var isBusy = false
    private(set) var status = "仅在本机保存"
    private(set) var blockedOperations = 0
    private(set) var lastSyncedAt: Date?
    private(set) var needsImportChoice = false
    private(set) var importSummary = ""
    var errorMessage: String?
    var proposedTimeZone: String?
    private var dismissedTimeZone: String?
    private var client: NestHTTPClient?
    private var engine: NestSyncEngine?
    private weak var store: SamoyedStore?
    private var webSession: ASWebAuthenticationSession?
    private var syncTask: Task<Void, Never>?
    private var needsSync = false
    private var restored = false
    var connected: Bool { user != nil && !needsImportChoice }

    func restore(store: SamoyedStore) async {
        self.store = store
        guard !restored else { return }; restored = true
        do {
            guard let c = try NestKeychain.load(), let user = c.user else { return }
            try c.capabilities.validate(origin: c.origin)
            let client = NestHTTPClient(credentials: c)
            self.client = client; self.user = user; origin = c.origin
            if c.bindingComplete { try activate(c); scheduleSync() }
            else { prepareImportChoice() }
        } catch { errorMessage = error.localizedDescription; status = "连接需要检查" }
    }

    func login(address: String, store: SamoyedStore) async {
        guard !isBusy, client == nil else { return }
        self.store = store; isBusy = true; errorMessage = nil; defer { isBusy = false }
        do {
            let origin = try NestHTTPClient.origin(address)
            let capabilities = try await NestHTTPClient.capabilities(origin: origin)
            let verifier = try randomToken(), state = try randomToken()
            let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded()
            var url = URLComponents(url: capabilities.auth.authorizationEndpoint, resolvingAgainstBaseURL: false)!
            url.queryItems = [
                .init(name: "client_id", value: capabilities.auth.clientID), .init(name: "response_type", value: "code"),
                .init(name: "redirect_uri", value: capabilities.auth.redirectURI), .init(name: "scope", value: capabilities.auth.scopes.joined(separator: " ")),
                .init(name: "resource", value: capabilities.auth.resource.absoluteString), .init(name: "code_challenge", value: challenge),
                .init(name: "code_challenge_method", value: "S256"), .init(name: "state", value: state), .init(name: "prompt", value: "login consent")
            ]
            let callback = try await authenticate(url.url!)
            guard let components = URLComponents(url: callback, resolvingAgainstBaseURL: false),
                  components.scheme == "top.protium.samoyed", components.host == nil, components.path == "/oauth/callback", components.fragment == nil else { throw NestHTTPError.invalidServer }
            let values = components.queryItems ?? []
            guard values.filter({ $0.name == "state" }).count == 1, values.first(where: { $0.name == "state" })?.value == state,
                  values.filter({ $0.name == "iss" }).count == 1, values.first(where: { $0.name == "iss" })?.value == capabilities.auth.issuer.absoluteString else { throw NestHTTPError.invalidServer }
            guard values.filter({ $0.name == "code" }).count == 1, let code = values.first(where: { $0.name == "code" })?.value, !code.isEmpty else { throw NestHTTPError.cancelled }
            let credentials = try await NestHTTPClient.exchange(origin: origin, capabilities: capabilities, code: code, verifier: verifier)
            let client = NestHTTPClient(credentials: credentials)
            let user = try await client.identify()
            self.client = client; self.user = user; self.origin = origin
            let saved = await client.snapshot()
            if let partition = saved.partition, try store.nestDatabase(partition: partition.key).cursor() != nil {
                try await client.completeBinding(); try activate(await client.snapshot()); scheduleSync()
            } else { prepareImportChoice() }
        } catch { errorMessage = error.localizedDescription; status = "未完成连接" }
    }

    private func prepareImportChoice() {
        needsImportChoice = true; status = "选择首次同步方式"
        let local = (try? store?.nestDatabase(partition: "local").load()) ?? .init()
        importSummary = "本机有 \(local.savedTemplates.count) 个 Routine、\(local.timelineNotes.filter { $0.deletedAt == nil }.count) 条 Note、\(local.dayPlans.count) 天历史。导入不会覆盖云端同名或同 ID 资料；原始资料会保留在本机迁移档案中。"
    }

    func bind(importLocal: Bool) async {
        guard let client, let store, !isBusy else { return }
        isBusy = true; errorMessage = nil; defer { isBusy = false }
        do {
            var c = await client.snapshot()
            guard let partition = c.partition else { throw NestHTTPError.invalidServer }
            if user?.timeZoneConfirmed == false {
                user = try await client.setTimeZone(TimeZone.current.identifier, expected: user!.timeZoneID)
                c = await client.snapshot()
            }
            let database = try store.nestDatabase(partition: partition.key)
            if try database.cursor() == nil {
                let initial = try await client.bootstrap()
                try database.apply(.init(cursor: initial.cursor, hasMore: false, changes: initial.entities))
            }
            if importLocal, let document = try store.nestDatabase(partition: "local").load() {
                try database.importLocal(document)
            }
            try await client.completeBinding()
            try activate(c); needsImportChoice = false; scheduleSync()
        } catch { errorMessage = error.localizedDescription; status = "首次同步未完成" }
    }

    private func activate(_ c: NestCredentials) throws {
        guard let store, let client, let partition = c.partition else { throw NestHTTPError.invalidServer }
        let database = try store.nestDatabase(partition: partition.key)
        engine = NestSyncEngine(database: database, transport: client)
        try store.switchNestPartition(partition.key)
        status = "等待同步"; checkTimeZone()
    }

    func scheduleSync() {
        guard connected, let engine, let client else { return }
        needsSync = true
        guard syncTask == nil else { return }
        syncTask = Task { [weak self] in
            guard let self else { return }
            defer { self.syncTask = nil }
            while self.needsSync && !Task.isCancelled {
                self.needsSync = false; self.status = "正在同步…"
                do {
                    try await engine.sync()
                    self.user = try await client.identify()
                    guard self.client === client else { return }
                    var calendar = Calendar(identifier: .gregorian)
                    calendar.timeZone = TimeZone(identifier: self.user?.timeZoneID ?? "UTC") ?? .gmt
                    let today = LocalDay.today(calendar: calendar)
                    let days = Set([today, today.adding(days: 1), self.store?.selectedDate ?? today])
                    for day in days { try await client.resolve(day) }
                    try await engine.sync()
                    guard !Task.isCancelled, self.client === client else { return }
                    if let partition = (await client.snapshot()).partition {
                        try self.store?.nestDatabase(partition: partition.key).saveScheduleCache(await client.scheduleCache())
                    }
                    self.store?.reload(); self.lastSyncedAt = .now
                    if let partition = (await client.snapshot()).partition { self.blockedOperations = try self.store?.nestDatabase(partition: partition.key).blockedOperationCount() ?? 0 }
                    self.status = self.blockedOperations == 0 ? "已同步" : "有 \(self.blockedOperations) 项修改需要处理"
                    self.errorMessage = nil
                    self.store?.recordNestDiagnostic()
                    self.checkTimeZone()
                } catch {
                    guard !Task.isCancelled else { return }
                    self.status = "等待重新同步"; self.errorMessage = error.localizedDescription
                    break
                }
            }
        }
    }

    func confirmTimeZone() async {
        guard let zone = proposedTimeZone, let user, let client else { return }
        do { self.user = try await client.setTimeZone(zone, expected: user.timeZoneID); proposedTimeZone = nil; scheduleSync() }
        catch { errorMessage = error.localizedDescription }
    }
    func retainTimeZone() { dismissedTimeZone = proposedTimeZone; proposedTimeZone = nil }
    private func checkTimeZone() {
        let zone = TimeZone.current.identifier
        if user?.timeZoneID != zone && dismissedTimeZone != zone { proposedTimeZone = zone }
    }

    func logout() async {
        syncTask?.cancel(); needsSync = false
        await client?.invalidate()
        do {
            try NestKeychain.clear(); try store?.switchNestPartition("local")
            client = nil; engine = nil; user = nil; origin = nil; syncTask = nil
            blockedOperations = 0; needsImportChoice = false; proposedTimeZone = nil; errorMessage = nil; lastSyncedAt = nil; status = "仅在本机保存"
        } catch { errorMessage = error.localizedDescription }
    }

    private func authenticate(_ url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "top.protium.samoyed") { url, error in
                if let url { continuation.resume(returning: url) }
                else { continuation.resume(throwing: error ?? NestHTTPError.cancelled) }
            }
            session.presentationContextProvider = self; session.prefersEphemeralWebBrowserSession = false
            webSession = session
            if !session.start() { webSession = nil; continuation.resume(throwing: NestHTTPError.cancelled) }
        }
    }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
    private func randomToken() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw CocoaError(.coderInvalidValue) }
        return Data(bytes).base64URLEncoded()
    }
}
private extension Data {
    func base64URLEncoded() -> String { base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
}
