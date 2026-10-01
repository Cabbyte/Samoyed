import Foundation

// `SamoyedDocumentRepository` 是共享文档的唯一 concrete 存储入口。
//
// 这层只负责三件事：
// App Group SQLite is the single write boundary for the app and extensions.
// Legacy JSON is imported once and retained as a migration backup.
//
// 它刻意“不知道” screen model、widget snapshot、页面状态这些上层概念。
// 这是为了避免“存储层顺便懂 UI”，导致维护时认知边界越来越糊。
struct SamoyedDocumentRepository {
    // `MutationOutcome` 是 mutate 的返回包装：
    // - `value`：调用方真正想拿到的业务结果
    // - `changed`：这次 mutate 是否真的改了 document
    // - `document`：变更后的最新 document
    struct MutationOutcome<Value> {
        let value: Value
        let changed: Bool
        let document: SamoyedDocument
    }

    enum RepositoryError: LocalizedError {
        case missingSharedContainer(String)
        case coordinationFailed(operation: String)

        var errorDescription: String? {
            switch self {
            case let .missingSharedContainer(identifier):
                return "Unable to access the shared container for \(identifier)."
            case let .coordinationFailed(operation):
                return "Unable to coordinate a shared document \(operation)."
            }
        }
    }

    private let documentURLOverride: URL?
    private let appGroupID: String?
    private let fileManager: FileManager
    private var partitionOverride: String?

    func scoped(to partition: String) -> Self {
        var copy = self
        copy.partitionOverride = partition
        return copy
    }

    var partition: String {
        partitionOverride ?? (appGroupID.flatMap { UserDefaults(suiteName: $0)?.string(forKey: "nest.activePartition") } ?? "local")
    }

    init(
        fileURL: URL,
        fileManager: FileManager = .default
    ) {
        // 这个初始化器主要给 preview / test 使用，
        // 允许直接指定一个临时 JSON 文件路径。
        documentURLOverride = fileURL
        appGroupID = nil
        self.fileManager = fileManager
    }

    private init(
        appGroupID: String,
        fileManager: FileManager = .default
    ) {
        // 这个初始化器主要给真实 app / widget 使用：
        // 默认从 app group 容器里找共享文档。
        documentURLOverride = nil
        self.appGroupID = appGroupID
        self.fileManager = fileManager
    }

    static var appLive: SamoyedDocumentRepository {
        SamoyedDocumentRepository(appGroupID: SamoyedSharedConfig.appGroupID)
    }

    static var widgetLive: SamoyedDocumentRepository {
        // widget 和主 app 共享同一份 document，只是入口不同。
        SamoyedDocumentRepository(appGroupID: SamoyedSharedConfig.appGroupID)
    }

    func load() throws -> SamoyedDocument? { try database().load() }

    func save(_ document: SamoyedDocument) throws {
        _ = try database().mutate { $0 = document }
    }

    /// Compare the caller's base with the latest transaction snapshot. Preserve unrelated
    /// extension writes and reject concurrent edits to the same object instead of losing data.
    func save(_ document: SamoyedDocument, mergingFrom base: SamoyedDocument) throws -> SamoyedDocument {
        try mutate { latest in
            latest = try NestDocumentMerge.merge(base: base, proposed: document, latest: latest)
        }.document
    }

    func mutate<Value>(_ body: (inout SamoyedDocument) throws -> Value) throws -> MutationOutcome<Value> {
        try database().mutate(body)
    }

    func database(partition: String? = nil) throws -> NestLocalDatabase {
        let legacyURL = try documentURL()
        return try NestLocalDatabase(url: legacyURL.deletingPathExtension().appendingPathExtension("sqlite"), partition: partition ?? self.partition, legacyURL: legacyURL)
    }

    private func documentURL() throws -> URL {
        if let documentURLOverride {
            return documentURLOverride
        }

        guard let appGroupID else {
            throw RepositoryError.missingSharedContainer("an unconfigured App Group")
        }
        guard let sharedContainerURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        ) else {
            throw RepositoryError.missingSharedContainer(appGroupID)
        }

        return sharedContainerURL
            .appending(path: SamoyedSharedConfig.sharedDirectoryName)
            .appending(path: SamoyedSharedConfig.documentFileName)
    }

}

enum NestDocumentMerge {
    static func merge(base: SamoyedDocument, proposed: SamoyedDocument, latest: SamoyedDocument) throws -> SamoyedDocument {
        func mergeItems<T: Equatable>(_ base: [T], _ proposed: [T], _ latest: [T], key: (T) -> String) throws -> [T] {
            func map(_ values: [T]) throws -> [String: T] {
                var result: [String: T] = [:]
                for value in values {
                    guard result.updateValue(value, forKey: key(value)) == nil else { throw CocoaError(.fileReadCorruptFile) }
                }
                return result
            }
            let old = try map(base), desired = try map(proposed), current = try map(latest)
            var result = latest
            for id in Set(old.keys).union(desired.keys) where old[id] != desired[id] {
                guard current[id] == old[id] || current[id] == desired[id] else { throw CocoaError(.fileWriteUnknown) }
                result.removeAll { key($0) == id }
                if let value = desired[id] { result.append(value) }
            }
            return result
        }
        var result = latest
        result.dayPlans = try mergeItems(base.dayPlans, proposed.dayPlans, latest.dayPlans) { $0.id.uuidString }
        result.savedTemplates = try mergeItems(base.savedTemplates, proposed.savedTemplates, latest.savedTemplates) { $0.id.uuidString }
        result.timelineNotes = try mergeItems(base.timelineNotes, proposed.timelineNotes, latest.timelineNotes) { $0.id.uuidString }
        result.weekdayRules = try mergeItems(base.weekdayRules, proposed.weekdayRules, latest.weekdayRules) { String($0.weekday.rawValue) }
        result.overrides = try mergeItems(base.overrides, proposed.overrides, latest.overrides) { "\($0.date.year)-\($0.date.month)-\($0.date.day)" }
        result.daySelections = try mergeItems(base.daySelections, proposed.daySelections, latest.daySelections) { "\($0.date.year)-\($0.date.month)-\($0.date.day):\($0.selectedAt.timeIntervalSince1970)" }
        return result
    }
}
