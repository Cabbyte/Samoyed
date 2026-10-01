import Foundation

// `PreviewSupport` 是 SwiftUI 预览专用的样本数据工厂。
// 它解决两个常见问题：
// 1. 预览想直接看到“像真实 app 一样”的画面，而不是一堆空白
// 2. 正式代码不应该混进大量 mock/演示数据构造逻辑
// 对 C++ 开发者可以理解成：专门给 UI 调试准备的一组 fixture / test data builder。
@MainActor
enum PreviewSupport {
    static var referenceDay: LocalDay {
        LocalDay.today()
    }

    static var generatedAt: Date {
        Date(timeIntervalSince1970: 1_710_000_000)
    }

    static func seededDocument(on referenceDay: LocalDay? = nil) -> SamoyedDocument {
        // `try!` 在生产代码里通常要谨慎，但在预览辅助里是合理的：
        // 如果样本数据都构不出来，预览本身就没有继续展示的意义。
        let day = referenceDay ?? self.referenceDay
        return try! SampleDataFactory.seededDocument(referenceDay: day, generatedAt: generatedAt)
    }

    static func store(
        tab: RootTab = .now,
        libraryNavigationPath: [LibraryDestination] = [],
        tintPreset: AppTintPreset = .ocean,
        selectedDate: LocalDay? = nil,
        loaded: Bool = true,
        document: SamoyedDocument? = nil,
        selectedBlockID: UUID? = nil,
        lastErrorMessage: String? = nil
    ) -> SamoyedStore {
        let day = selectedDate ?? referenceDay
        // 每个预览实例都拿一份独立的临时文件地址。
        // 这样多个 preview 不会互相污染，也不会误碰真实 app 文档。
        let documentRepository = SamoyedDocumentRepository(
            fileURL: FileManager.default.temporaryDirectory
                .appending(path: "SamoyedPreview")
                .appending(path: "\(UUID().uuidString).json")
        )
        let store = SamoyedStore(documentRepository: documentRepository)
        store.selectedTab = tab
        store.libraryNavigationPath = libraryNavigationPath
        store.tintPreset = tintPreset
        store.selectedDate = day

        if loaded {
            store.document = document ?? seededDocument(on: day)
            store.isLoaded = true
            store.bootstrapState = .ready
            store.ensureMaterialized(for: day)
            store.selectedBlockID = selectedBlockID
        }

        if let lastErrorMessage {
            store.presentErrorMessage(lastErrorMessage)
        }

        return store
    }

    static func nowModel(
        document: SamoyedDocument? = nil,
        minuteOfDay: Int = 9 * 60 + 30
    ) -> NowScreenModel {
        // 这里直接调用 presentation 层，而不是先造一个完整 store。
        // 好处是：
        // - 预览更轻
        // - 更适合单独验证“某个 View 的布局是否正确”
        let day = referenceDay
        return try! SamoyedPresentation.nowScreenModel(
            document: document ?? seededDocument(on: day),
            date: day,
            minuteOfDay: minuteOfDay
        )
    }

    static func todayModel(
        document: SamoyedDocument? = nil,
        selectedBlockID: UUID? = nil,
        currentMinute: Int? = 9 * 60 + 30
    ) -> TodayScreenModel {
        let day = referenceDay
        return try! SamoyedPresentation.todayScreenModel(
            document: document ?? seededDocument(on: day),
            date: day,
            selectedBlockID: selectedBlockID,
            currentMinute: currentMinute
        )
    }

    static func templatesModel(document: SamoyedDocument? = nil) -> TemplatesScreenModel {
        let day = referenceDay
        return try! SamoyedPresentation.templatesScreenModel(
            document: document ?? seededDocument(on: day),
            referenceDay: day
        )
    }

    static func savedTemplate(document: SamoyedDocument? = nil) -> SavedDayTemplate {
        let resolvedDocument = document ?? seededDocument()
        return resolvedDocument.savedTemplates.last!
    }

    static func emptyTemplate() -> SavedDayTemplate {
        SavedDayTemplate(
            title: "No Routine",
            sourceSuggestedTemplateID: UUID(),
            blocks: []
        )
    }

    static func selectedBlockDetailModel() -> BlockDetailModel {
        // 预览经常需要一个“当前选中的 block 详情”来驱动编辑器或详情页。
        todayModel().selectedBlock!
    }

    static func persistedSelectedBlock() -> TimeBlock {
        // 这里拿的是 document 里真正持久化的 `TimeBlock`，而不是 screen model。
        // 学习时要特别注意这两者的区别：前者是业务真值，后者是给界面展示的投影。
        let document = seededDocument()
        let detail = selectedBlockDetailModel()
        return document.dayPlan(for: referenceDay)!.blocks.first(where: { $0.id == detail.id })!
    }

}
