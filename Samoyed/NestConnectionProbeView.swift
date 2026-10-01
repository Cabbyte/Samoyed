import AuthenticationServices
import SwiftUI

/// Stage A diagnostics. This view cannot create a Nest session or authorize synchronization.
struct NestConnectionProbeView: View {
    @State private var probe = NestConnectionProbe()
    var body: some View {
        NavigationStack {
            Form {
                Section("Sites native access verification") {
                    Text("This checks browser identity separately from native URLSession access. It does not connect your local data.")
                    Button("1. Test native requests") { Task { await probe.testAPI() } }
                    Button("2. Open ChatGPT sign-in") { probe.signIn() }
                    Button("3. Test again after closing sign-in") { Task { await probe.testAPI() } }
                }
                Section("Results") { ForEach(Array(probe.messages.enumerated()), id: \.offset) { _, message in Text(message).font(.caption.monospaced()) } }
            }.navigationTitle("Nest connection probe").task { await probe.testAPI() }
        }
    }
}

@MainActor @Observable
final class NestConnectionProbe: NSObject, ASWebAuthenticationPresentationContextProviding {
    var messages: [String] = []
    private var session: ASWebAuthenticationSession?
    private let origin = "https://samoyed-nest.timli0617.chatgpt.site"
    private let native = URLSession(configuration: .ephemeral)
    func testAPI() async {
        for path in ["/v1/capabilities", "/v1/identity", "/.well-known/oauth-protected-resource/mcp"] {
            do {
                let (_, response) = try await native.data(from: URL(string: origin + path)!)
                record("URLSession \(path): HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
            } catch { record("URLSession \(path): \((error as NSError).domain) \((error as NSError).code)") }
        }
    }
    func signIn() {
        let state = UUID().uuidString.lowercased()
        var components = URLComponents(string: origin + "/signin-with-chatgpt")!
        components.queryItems = [URLQueryItem(name: "return_to", value: "/native-probe/return?state=\(state)")]
        session = ASWebAuthenticationSession(url: components.url!, callbackURLScheme: "samoyed") { [weak self] url, error in
            Task { @MainActor in
                guard let self else { return }
                defer { self.session = nil }
                if let url, let parts = URLComponents(url: url, resolvingAgainstBaseURL: false), parts.queryItems?.first(where: { $0.name == "state" })?.value == state {
                    self.record("Browser returned. authenticated=\(parts.queryItems?.first(where: { $0.name == "browserAuthenticated" })?.value ?? "unknown"). No device credential issued.")
                } else { self.record("Browser closed (\((error as NSError?)?.code ?? 0)).") }
                await self.testAPI()
            }
        }
        session?.presentationContextProvider = self
        session?.start()
    }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
    private func record(_ message: String) {
        messages.append(message)
        let text = messages.joined(separator: "\n")
        if let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            try? Data(text.utf8).write(to: directory.appendingPathComponent("nest-connection-probe.txt"), options: .atomic)
        }
    }
}

#if DEBUG
/// Controlled transport-failure acceptance in a separate test database. Never reads
/// or changes the normal account, Keychain, App Group partition or local documents.
struct NestDeviceAcceptanceView: View {
    @State private var message = "正在运行独立测试账户验收…"
    var body: some View { Text(message).padding().task { message = await NestDeviceAcceptance.run() } }
}
private enum NestDeviceAcceptance {
    struct Input: Decodable { var origin: URL; var accessToken: String; var userID: String; var day: LocalDay; var noteID: UUID }
    static func run() async -> String {
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let phase = ProcessInfo.processInfo.arguments.first { $0.hasPrefix("--nest-acceptance-") } ?? "unknown"
        var report: [String: String] = ["phase": phase, "recordedAt": ISO8601DateFormatter().string(from: .now)]
        do {
            let input = try JSONDecoder().decode(Input.self, from: Data(contentsOf: folder.appendingPathComponent("nest-acceptance-input.json")))
            guard input.origin.absoluteString == "https://samoyed.protium.top", input.userID == "b734a718-63ce-4d99-ae1e-9fe6be2e62de" else { throw CocoaError(.coderInvalidValue) }
            func get(_ path: String) async throws -> Data {
                var request = URLRequest(url: input.origin.appendingPathComponent(path)); request.setValue("Bearer " + input.accessToken, forHTTPHeaderField: "Authorization")
                let (data, response) = try await URLSession.shared.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.userAuthenticationRequired) }
                return data
            }
            struct Identity: Decodable { var user: NestCloudUser }
            guard try JSONDecoder().decode(Identity.self, from: await get("v1/identity")).user.id == input.userID else { throw CocoaError(.coderInvalidValue) }
            let database = try NestLocalDatabase(url: folder.appendingPathComponent("nest-acceptance.sqlite"), partition: "isolated-device-acceptance")
            let transport = try NestURLSessionTransport(origin: input.origin, accessToken: input.accessToken)
            if phase == "--nest-acceptance-offline" {
                guard try database.cursor() == nil else { throw CocoaError(.fileWriteFileExists) }
                let boot = try JSONDecoder().decode(NestBootstrap.self, from: await get("v1/sync/bootstrap"))
                try database.apply(.init(cursor: boot.cursor, hasMore: false, changes: boot.entities))
                try database.saveScheduleCache(JSONDecoder().decode(NestScheduleCache.self, from: await get("v1/schedule-cache")))
                guard let plan = try database.materializeCachedDay(input.day), let block = plan.blocks.first, let task = block.tasks.first else { throw CocoaError(.coderValueNotFound) }
                _ = try database.mutate { document in
                    let p = document.dayPlans.firstIndex { $0.id == plan.id }!
                    document.dayPlans[p].blocks[0].tasks[0].isCompleted = true; document.dayPlans[p].blocks[0].tasks[0].completedAt = .now
                }
                _ = try database.mutate { document in
                    let p = document.dayPlans.firstIndex { $0.id == plan.id }!
                    document.dayPlans[p].blocks[0].tasks[0].isCompleted = false; document.dayPlans[p].blocks[0].tasks[0].completedAt = nil
                    document.timelineNotes.append(TimelineNote(id: input.noteID, text: "Device controlled-offline acceptance", occurredAt: Date(timeIntervalSince1970: 1790841600), timeZoneID: "Asia/Shanghai"))
                }
                do { try await NestSyncEngine(database: database, transport: NestAcceptanceFailure(base: transport, sendBeforeFailing: false)).sync(); throw CocoaError(.coderInvalidValue) }
                catch let error as URLError where error.code == .notConnectedToInternet { }
                report["planID"] = plan.id.uuidString.lowercased(); report["taskID"] = task.id.uuidString.lowercased()
                guard try database.pendingOperations().count == 4 else { throw CocoaError(.coderInvalidValue) }
            } else if phase == "--nest-acceptance-lost-response" {
                guard try database.pendingOperations().count == 4 else { throw CocoaError(.coderInvalidValue) }
                do { try await NestSyncEngine(database: database, transport: NestAcceptanceFailure(base: transport, sendBeforeFailing: true)).sync(); throw CocoaError(.coderInvalidValue) }
                catch let error as URLError where error.code == .networkConnectionLost { }
                guard try database.pendingOperations().count == 4 else { throw CocoaError(.coderInvalidValue) }
            } else if phase == "--nest-acceptance-recover" {
                try await NestSyncEngine(database: database, transport: transport).sync()
                guard try database.pendingOperations().isEmpty, try database.blockedOperationCount() == 0,
                      let document = try database.load(), document.timelineNotes.contains(where: { $0.id == input.noteID }),
                      document.dayPlan(for: input.day)?.blocks.first?.tasks.first?.isCompleted == false else { throw CocoaError(.coderInvalidValue) }
                report["pendingOperations"] = "0"; report["blockedOperations"] = "0"
                try FileManager.default.removeItem(at: folder.appendingPathComponent("nest-acceptance-input.json"))
            } else { throw CocoaError(.coderInvalidValue) }
            report["result"] = "passed"
        } catch {
            report["result"] = "failed"; report["errorDomain"] = (error as NSError).domain; report["errorCode"] = String((error as NSError).code)
        }
        try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]).write(to: folder.appendingPathComponent("nest-acceptance-result.json"), options: .atomic)
        return report["result"] == "passed" ? "独立测试阶段完成" : "独立测试需要检查"
    }
}
private actor NestAcceptanceFailure: NestSyncTransport {
    let base: NestURLSessionTransport; let sendBeforeFailing: Bool
    init(base: NestURLSessionTransport, sendBeforeFailing: Bool) { self.base = base; self.sendBeforeFailing = sendBeforeFailing }
    func push(_ operations: [NestSyncCommand]) async throws -> [NestPushResult] {
        if sendBeforeFailing {
            let results = try await base.push(operations)
            guard results.allSatisfy({ $0.status == "accepted" }) else { throw CocoaError(.coderInvalidValue) }
        }
        throw URLError(sendBeforeFailing ? .networkConnectionLost : .notConnectedToInternet)
    }
    func pull(cursor: String) async throws -> NestPullPage { throw URLError(.notConnectedToInternet) }
}
#endif
