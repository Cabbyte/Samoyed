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
    private var sessionID = UUID()
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
        self.store = store; isBusy = true; errorMessage = nil
        let sessionID = self.sessionID
        defer { if self.sessionID == sessionID { isBusy = false } }
        do {
            let origin = try NestHTTPClient.origin(address)
            let capabilities = try await NestHTTPClient.capabilities(origin: origin)
            guard self.sessionID == sessionID, !Task.isCancelled else { return }
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
            guard self.sessionID == sessionID, !Task.isCancelled else { return }
            let code = try NestLoginCallback.code(from: callback, state: state, issuer: capabilities.auth.issuer)
            let credentials = try await NestHTTPClient.exchange(origin: origin, capabilities: capabilities, code: code, verifier: verifier)
            guard self.sessionID == sessionID, !Task.isCancelled else { return }
            let client = NestHTTPClient(credentials: credentials)
            self.client = client
            let user = try await client.identify()
            try ensureCurrent(client)
            self.user = user; self.origin = origin
            let saved = await client.snapshot()
            try ensureCurrent(client)
            if let partition = saved.partition, try store.nestDatabase(partition: partition.key).cursor() != nil {
                try await client.completeBinding()
                let bound = await client.snapshot()
                try ensureCurrent(client)
                try activate(bound); scheduleSync()
            } else { prepareImportChoice() }
        } catch {
            guard self.sessionID == sessionID else { return }
            if let client { await client.invalidate() }
            guard self.sessionID == sessionID else { return }
            self.client = nil; user = nil; self.origin = nil
            errorMessage = error.localizedDescription; status = "未完成连接"
        }
    }

    private func prepareImportChoice() {
        needsImportChoice = true; status = "选择首次同步方式"
        let local = (try? store?.nestDatabase(partition: "local").load()) ?? .init()
        importSummary = "本机有 \(local.savedTemplates.count) 个 Routine、\(local.timelineNotes.filter { $0.deletedAt == nil }.count) 条 Note、\(local.dayPlans.count) 天历史。导入不会覆盖云端同名或同 ID 资料；原始资料会保留在本机迁移档案中。"
    }

    func bind(importLocal: Bool) async {
        guard let client, let store, !isBusy else { return }
        isBusy = true; errorMessage = nil; defer { if self.client === client { isBusy = false } }
        do {
            var c = await client.snapshot()
            try ensureCurrent(client)
            guard let partition = c.partition else { throw NestHTTPError.invalidServer }
            if user?.timeZoneConfirmed == false {
                let updated = try await client.setTimeZone(TimeZone.current.identifier, expected: user!.timeZoneID)
                try ensureCurrent(client)
                user = updated
                c = await client.snapshot()
                try ensureCurrent(client)
            }
            let database = try store.nestDatabase(partition: partition.key)
            if try database.cursor() == nil {
                let initial = try await client.bootstrap()
                try ensureCurrent(client)
                try database.apply(.init(cursor: initial.cursor, hasMore: false, changes: initial.entities))
            }
            if importLocal, let document = try store.nestDatabase(partition: "local").load() {
                try database.importLocal(document)
            }
            try await client.completeBinding()
            try ensureCurrent(client)
            try activate(c); needsImportChoice = false; scheduleSync()
        } catch { guard self.client === client else { return }; errorMessage = error.localizedDescription; status = "首次同步未完成" }
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
            defer { if self.client === client { self.syncTask = nil } }
            while self.needsSync && !Task.isCancelled {
                self.needsSync = false; self.status = "正在同步…"
                do {
                    try await engine.sync()
                    try self.ensureCurrent(client)
                    let freshUser = try await client.identify()
                    try self.ensureCurrent(client)
                    self.user = freshUser
                    var calendar = Calendar(identifier: .gregorian)
                    calendar.timeZone = TimeZone(identifier: self.user?.timeZoneID ?? "UTC") ?? .gmt
                    let today = LocalDay.today(calendar: calendar)
                    let days = Set([today, today.adding(days: 1), self.store?.selectedDate ?? today])
                    for day in days { try await client.resolve(day) }
                    try await engine.sync()
                    guard !Task.isCancelled, self.client === client else { return }
                    let snapshot = await client.snapshot()
                    try self.ensureCurrent(client)
                    if let partition = snapshot.partition {
                        let cache = try await client.scheduleCache()
                        try self.ensureCurrent(client)
                        let database = try self.store?.nestDatabase(partition: partition.key)
                        try database?.saveScheduleCache(cache)
                        self.blockedOperations = try database?.blockedOperationCount() ?? 0
                    }
                    self.store?.reload(); self.lastSyncedAt = .now
                    self.status = self.blockedOperations == 0 ? "已同步" : "有 \(self.blockedOperations) 项修改需要处理"
                    self.errorMessage = nil
                    self.store?.recordNestDiagnostic()
                    self.checkTimeZone()
                } catch {
                    guard !Task.isCancelled, self.client === client else { return }
                    self.status = "等待重新同步"; self.errorMessage = error.localizedDescription
                    break
                }
            }
        }
    }

    func confirmTimeZone() async {
        guard let zone = proposedTimeZone, let user, let client else { return }
        do {
            let updated = try await client.setTimeZone(zone, expected: user.timeZoneID)
            try ensureCurrent(client)
            self.user = updated; proposedTimeZone = nil; scheduleSync()
        } catch { guard self.client === client else { return }; errorMessage = error.localizedDescription }
    }
    func retainTimeZone() { dismissedTimeZone = proposedTimeZone; proposedTimeZone = nil }
    private func checkTimeZone() {
        let zone = TimeZone.current.identifier
        if user?.timeZoneID != zone && dismissedTimeZone != zone { proposedTimeZone = zone }
    }

    func logout() async {
        sessionID = UUID()
        let retiringClient = client
        let logoutID = sessionID
        isBusy = true; webSession?.cancel(); webSession = nil
        syncTask?.cancel(); needsSync = false
        client = nil; engine = nil; user = nil; origin = nil; syncTask = nil
        blockedOperations = 0; needsImportChoice = false; proposedTimeZone = nil
        dismissedTimeZone = nil; errorMessage = nil; lastSyncedAt = nil; status = "仅在本机保存"
        // Change the visible/write partition before any suspension, even if keychain cleanup fails.
        do { try store?.switchNestPartition("local") }
        catch { errorMessage = error.localizedDescription }
        await retiringClient?.invalidate()
        guard sessionID == logoutID else { return }
        defer { isBusy = false }
        do {
            try NestKeychain.clear()
        } catch { if errorMessage == nil { errorMessage = error.localizedDescription } }
    }

    private func ensureCurrent(_ client: NestHTTPClient) throws {
        guard !Task.isCancelled, self.client === client else { throw NestHTTPError.cancelled }
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
