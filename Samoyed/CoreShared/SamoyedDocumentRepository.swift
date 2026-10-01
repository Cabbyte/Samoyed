import Foundation

// `SamoyedDocumentRepository` 是共享文档的唯一 concrete 存储入口。
//
// 这层只负责三件事：
// 1. 找到 document.json 在哪里
// 2. 原子地读/写这份 JSON
// 3. 在需要时做带文件协调(file coordination)的 mutate
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

    func load() throws -> SamoyedDocument? {
        // “文件不存在”在这里不是异常，而是“尚未初始化”的正常状态。
        let url = try documentURL()

        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }

        return try coordinateReading(url) { coordinatedURL in
            try readDocument(from: coordinatedURL)
        }
    }

    func save(_ document: SamoyedDocument) throws {
        // save 不做业务级校验，只负责写盘。
        let url = try documentURL()
        try coordinateWriting(url) { coordinatedURL in
            try writeDocument(document, to: coordinatedURL)
        }
    }

    func mutate<Value>(
        _ body: (inout SamoyedDocument) throws -> Value
    ) throws -> MutationOutcome<Value> {
        // `mutate` 是这里最值得学习的方法：
        // 它把“读当前文档 -> 在内存里修改 -> 如果有变化则原子写回”封装成一个模板。
        // 这样调用者只需要关心“我要怎么改 document”，不用重复写存储样板代码。
        let url = try documentURL()

        return try coordinateWriting(url) { coordinatedURL in
            let current = try readDocumentIfPresent(from: coordinatedURL) ?? SamoyedDocument()
            var updated = current
            let value = try body(&updated)

            // 只有 document 真变了才写盘，避免无意义 I/O。
            if updated != current {
                try writeDocument(updated, to: coordinatedURL)
            }

            return MutationOutcome(
                value: value,
                changed: updated != current,
                document: updated
            )
        }
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

    private func coordinateReading<T>(
        _ url: URL,
        body: (URL) throws -> T
    ) throws -> T {
        // `NSFileCoordinator` 用于 app / widget / extension 间共享文件访问协调。
        // 不用它也可能“看起来能跑”，但并发访问时更容易出数据竞争问题。
        var coordinationError: NSError?
        var result: Result<T, Error>?

        NSFileCoordinator(filePresenter: nil).coordinate(
            readingItemAt: url,
            options: [],
            error: &coordinationError
        ) { coordinatedURL in
            result = Result {
                try body(coordinatedURL)
            }
        }

        if let result {
            return try result.get()
        }
        if let coordinationError {
            throw coordinationError
        }
        throw RepositoryError.coordinationFailed(operation: "read")
    }

    private func coordinateWriting<T>(
        _ url: URL,
        body: (URL) throws -> T
    ) throws -> T {
        // 写前先确保目录存在，这是文件存储层最常见的防御式步骤。
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var coordinationError: NSError?
        var result: Result<T, Error>?

        NSFileCoordinator(filePresenter: nil).coordinate(
            writingItemAt: url,
            options: .forMerging,
            error: &coordinationError
        ) { coordinatedURL in
            result = Result {
                try body(coordinatedURL)
            }
        }

        if let result {
            return try result.get()
        }
        if let coordinationError {
            throw coordinationError
        }
        throw RepositoryError.coordinationFailed(operation: "write")
    }

    private func readDocumentIfPresent(from url: URL) throws -> SamoyedDocument? {
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }

        return try readDocument(from: url)
    }

    private func readDocument(from url: URL) throws -> SamoyedDocument {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(SamoyedDocument.self, from: data)
    }

    private func writeDocument(
        _ document: SamoyedDocument,
        to url: URL
    ) throws {
        // `.atomic` 会先写临时文件，再替换正式文件，能减少半写入损坏风险。
        let data = try prettyEncoder().encode(document)
        try data.write(to: url, options: .atomic)
    }

    private func prettyEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
