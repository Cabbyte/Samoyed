import Foundation
import Observation
import WidgetKit

// `RootTab` 是最顶层 TabView 的选中状态。
// 用 enum 而不是 `Int` / `String` 的好处是：
// 1. 编译器能帮你检查分支是否处理完整
// 2. 改名字时 IDE 可以全局安全重构
enum RootTab: Hashable {
    case now
    case today
    case library
}

enum DayTemplateChoiceCommandResult: Equatable {
    case applied
    case requiresConfirmation
}

enum AppBootstrapState: Equatable {
    case loading
    case needsActivation
    case ready
    case loadError(String)
}

struct TaskCompletionReference: Equatable {
    let date: LocalDay
    let blockID: UUID
    let taskID: UUID
}

// `SamoyedStore` 是整个 app 的 UI 状态中枢。
//
// 如果你来自 C++，可以把它理解成下面三者的混合体：
// - 一部分像“应用级 controller”
// - 一部分像“view model / presenter”
// - 一部分像“command dispatcher”
//
// 它并不是纯业务层；真正的业务规则在 CoreShared 的各个 engine 里。
// 它的职责是：
// 1. 持有当前已加载的 document
// 2. 把 document 转成屏幕需要的 model
// 3. 响应用户操作并把结果持久化
// 4. 在文档变更后同步 widget / live activity / notification
@MainActor
@Observable
final class SamoyedStore {
    // MARK: State

    // `document` 是持久化数据在内存中的“当前快照”。
    // SwiftUI 页面几乎都间接依赖它。
    var document: SamoyedDocument = .init()
    var tintPreset: AppTintPreset

    // 这些字段是 UI 层状态，而不是业务模型本身：
    // - 当前哪个 tab 被选中
    // - Library 是否推到了某个子页面
    // - 当前选中的日期和 block
    var selectedTab: RootTab = .now {
        didSet {
            // 当用户切换顶层 tab 时，之前选中的 block 详情通常已失去上下文，
            // 所以这里直接清掉，避免旧选择“穿透”到新页面。
            guard oldValue != selectedTab else { return }
            selectedBlockID = nil
        }
    }
    var libraryNavigationPath: [LibraryDestination] = []
    var selectedDate: LocalDay = LocalDay.today()
    var selectedBlockID: UUID?
    var isLoaded = false
    var bootstrapState: AppBootstrapState = .loading
    private(set) var lastErrorMessage: String?

    // Store 本身不直接读写 JSON 文件，而是依赖一个 concrete repository。
    // 这样做有两个教育意义：
    // 1. UI 层不碰文件系统细节
    // 2. 预览/测试可以替换 repository 的落点
    private let documentRepository: SamoyedDocumentRepository
    private let validationLogger: ValidationEventLogger
    private let feedbackService: FeedbackService
    private let suggestionService: SuggestionService
    private var nowVisibleDays: Set<LocalDay> = []

    init(
        documentRepository: SamoyedDocumentRepository = .appLive,
        validationLogger: ValidationEventLogger = .shared
    ) {
        // tint 偏好是 UI 级偏好，不属于 document。
        tintPreset = SamoyedTintPreference.load()
        self.documentRepository = documentRepository
        self.validationLogger = validationLogger
        feedbackService = FeedbackService(repository: documentRepository)
        suggestionService = SuggestionService(repository: documentRepository)
    }

    // MARK: Bootstrap

    func loadIfNeeded() {
        // SwiftUI 视图可能多次出现/重建，这里确保真正的加载只做一次。
        guard !isLoaded else { return }
        bootstrapDocument()
    }

    func bootstrapDocument() {
        if bootstrapState != .ready {
            bootstrapState = .loading
        }
        do {
            // A missing document is a real first-run state, not an invitation to seed production data.
            if let loaded = try documentRepository.load() {
                document = loaded
            } else {
                document = SamoyedDocument()
            }

            isLoaded = true
            dismissError()
            if document.isEmptyForActivation {
                bootstrapState = .needsActivation
            } else {
                bootstrapState = .ready
                ensureMaterialized(for: selectedDate)
            }
        } catch {
            isLoaded = true
            bootstrapState = .loadError(error.localizedDescription)
        }
    }

    func reload() {
        bootstrapDocument()
    }

    func retryBootstrap() {
        bootstrapState = .loading
        isLoaded = false
        bootstrapDocument()
    }

    // MARK: Navigation

    // “materialize” 是这个项目里的关键术语：
    // 表示“确保某个日期真的有一份具体 DayPlan 可以读”。
    // 如果当天还没有 plan，但模板规则能推导出一个，就在这里生成。
    func ensureMaterialized(for date: LocalDay) {
        do {
            guard bootstrapState == .ready else { return }

            let materialized = try TemplateEngine.ensureMaterializedDayPlan(
                for: date,
                existingDayPlans: document.dayPlans,
                savedTemplates: document.savedTemplates,
                weekdayRules: document.weekdayRules,
                overrides: document.overrides,
                daySelections: document.daySelections
            )

            if document.dayPlan(for: date) == nil {
                // 注意：这里不仅更新内存，还会持久化。
                // 因为“自动从模板推导出当天计划”也属于 document 的一部分。
                upsert(dayPlan: materialized)
                try persistDocument()
            }
        } catch {
            presentError(error)
        }
    }

    func selectDate(_ date: LocalDay) {
        // 选日期不是纯 UI 行为，它会触发 day plan 实体化。
        selectedDate = date
        selectedBlockID = nil
        ensureMaterialized(for: date)
    }

    func moveSelectedDate(by dayOffset: Int) {
        selectDate(selectedDate.adding(days: dayOffset))
    }

    func selectBlock(_ blockID: UUID?) {
        selectedBlockID = blockID
    }

    func openLibrary(destination: LibraryDestination? = nil) {
        // 这是显式导航命令，比直接在外部改 `selectedTab`/`path` 更安全。
        selectedTab = .library
        libraryNavigationPath = destination.map { [$0] } ?? []
    }

    func showNow() {
        selectedTab = .now
        selectedBlockID = nil
    }

    func showToday(date: LocalDay? = nil, blockID: UUID? = nil) {
        // 这里体现了“系统路由 -> store 命令 -> UI 状态”的思路。
        // 外部只需要给出“我想展示 today + 某个 block”，
        // 具体如何更新 tab / date / selection 由 store 统一处理。
        selectedTab = .today

        if let date {
            selectDate(date)
        } else {
            selectedBlockID = nil
        }

        selectBlock(blockID)
    }

    func showLibrary() {
        openLibrary()
    }

    func requiresTemplateSelection(
        for date: LocalDay,
        today: LocalDay = .today()
    ) -> Bool {
        _ = date
        _ = today
        return false
    }

    func todayTemplateChooserModel(for date: LocalDay? = nil) throws -> DayTemplateChooserModel {
        let resolvedDate = date ?? LocalDay.today()
        return try SamoyedPresentation.templatesScreenModel(
            document: document,
            referenceDay: resolvedDate
        ).todayChooser
    }

    func applyTintPreset(_ preset: AppTintPreset) {
        guard tintPreset != preset else { return }

        tintPreset = preset
        SamoyedTintPreference.save(preset)
        // 改主题色不仅影响 app，自定义 widget/live activity 也要刷新。
        refreshVisualSystemSurfaces()
    }

    func presentError(_ error: Error) {
        // Store 只保存一个“可展示的错误消息”，让根视图统一弹窗。
        lastErrorMessage = error.localizedDescription
    }

    func presentErrorMessage(_ message: String) {
        lastErrorMessage = message
    }

    func dismissError() {
        lastErrorMessage = nil
    }

    // MARK: Queries

    func minuteOfDay(for date: Date) -> Int {
        // 这类小 helper 让 View 层不需要直接碰 DateComponents 细节。
        date.minuteOfDay
    }

    func currentMinuteOnSelectedDate(currentDate: Date = .now) -> Int? {
        // 只有当 selectedDate 正好是“今天”时，当前时间才有意义。
        // 看历史日期时，不应该把 now 的红线/焦点带进去。
        guard selectedDate == LocalDay(date: currentDate) else { return nil }
        return currentDate.minuteOfDay
    }

    func nowScreenModel(at date: Date) throws -> NowScreenModel {
        // Query 方法的标准模式：
        // 1. 先确保 document 已准备好
        // 2. 调用纯 presentation 层做映射
        let localDay = LocalDay(date: date)
        ensureMaterialized(for: localDay)
        return try SamoyedPresentation.nowScreenModel(
            document: document,
            date: localDay,
            minuteOfDay: date.minuteOfDay
        )
    }

    func todayScreenModel(currentDate: Date = .now) throws -> TodayScreenModel {
        // 这里没有直接操作 SwiftUI View，而是返回一个“屏幕所需数据包”。
        // 这让页面能保持更薄，也更容易测试。
        ensureMaterialized(for: selectedDate)
        return try SamoyedPresentation.todayScreenModel(
            document: document,
            date: selectedDate,
            selectedBlockID: selectedBlockID,
            currentMinute: currentMinuteOnSelectedDate(currentDate: currentDate)
        )
    }

    func currentActiveBlockID(currentDate: Date = .now) -> UUID? {
        // `currentActiveBlockID` 主要服务于系统入口或页面初始焦点。
        let localDay = LocalDay(date: currentDate)
        guard selectedDate == localDay else { return nil }

        ensureMaterialized(for: selectedDate)
        let plan = document.dayPlan(for: selectedDate) ?? DayPlan(date: selectedDate)

        return try? DayPlanEngine.activeSelection(
            in: plan,
            at: currentDate.minuteOfDay
        ).chain.reversed().first(where: { !$0.isBlankBaseBlock })?.id
    }

    func templatesScreenModel(referenceDay: LocalDay? = nil) throws -> TemplatesScreenModel {
        // 模板页会同时展示“今天”和“明天”的调度情况，所以这里会确保两天都 materialize。
        let resolvedReferenceDay = referenceDay ?? LocalDay.today()
        ensureMaterialized(for: resolvedReferenceDay)
        ensureMaterialized(for: resolvedReferenceDay.adding(days: 1))
        return try SamoyedPresentation.templatesScreenModel(
            document: document,
            referenceDay: resolvedReferenceDay
        )
    }

    var selectedBlockDetail: BlockDetailModel? {
        // 这是“派生状态”，不是独立存储。
        // 好处是：源数据始终只有 document + selectedDate + selectedBlockID。
        guard isLoaded, let selectedBlockID else {
            return nil
        }

        return try? blockDetailModel(on: selectedDate, blockID: selectedBlockID)
    }

    func blockDetailModel(on date: LocalDay, blockID: UUID) throws -> BlockDetailModel? {
        // 这里复用了 today 的 presentation 结果，而不是再手写一遍 block detail 映射。
        let todayModel = try SamoyedPresentation.todayScreenModel(
            document: document,
            date: date,
            selectedBlockID: blockID,
            currentMinute: nil
        )
        return todayModel.selectedBlock
    }

    var savedTemplates: [SavedDayTemplate] {
        document.savedTemplates
    }

    func savedTemplate(id: UUID) -> SavedDayTemplate? {
        document.savedTemplates.first(where: { $0.id == id })
    }

    func assignedTemplateID(for weekday: Weekday) -> UUID? {
        document.weekdayRules.first(where: { $0.weekday == weekday })?.savedTemplateID
    }

    func overrideTemplateID(for date: LocalDay) -> UUID? {
        document.overrides.first(where: { $0.date == date })?.savedTemplateID
    }

    var tomorrowOverrideTemplateID: UUID? {
        overrideTemplateID(for: LocalDay.today().adding(days: 1))
    }

    var isReady: Bool {
        bootstrapState == .ready
    }
    func persistedBlock(on date: LocalDay, blockID: UUID) -> TimeBlock? {
        // “persistedBlock” 和 `BlockDetailModel` 的区别：
        // - 前者是 document 里真实存储的业务对象
        // - 后者是给 UI 用的展示模型
        document.dayPlan(for: date)?.blocks.first(where: { $0.id == blockID })
    }

    func previewRoutineConfigImport(_ yaml: String) throws -> PortableDayBlocksSummary {
        try SamoyedPortableDayBlocks.summary(fromYAML: yaml)
    }

    @discardableResult
    func importRoutineConfigYAML(
        _ yaml: String,
        title rawTitle: String,
        replacingRoutineID: UUID? = nil
    ) throws -> UUID {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            throw SamoyedCoreError.emptyTemplateTitle
        }

        let importedPlan = try SamoyedPortableDayBlocks.dayPlanForImport(
            fromYAML: yaml,
            on: LocalDay(year: 2001, month: 1, day: 1)
        )
        let existingRoutine = replacingRoutineID.flatMap(savedTemplate(id:))
        let routine = SavedDayTemplate(
            id: existingRoutine?.id ?? UUID(),
            title: title,
            sourceSuggestedTemplateID: existingRoutine?.sourceSuggestedTemplateID ?? UUID(),
            blocks: blockTemplates(from: importedPlan.blocks),
            createdAt: existingRoutine?.createdAt ?? .now,
            updatedAt: .now
        )

        _ = try TemplateEngine.previewDayPlan(from: routine)
        if let index = document.savedTemplates.firstIndex(where: { $0.id == replacingRoutineID }) {
            document.savedTemplates[index] = routine
        } else {
            document.savedTemplates.append(routine)
        }
        try persistDocument()
        if bootstrapState == .needsActivation {
            bootstrapState = .ready
        }
        return routine.id
    }

    func routineID(titled rawTitle: String) -> UUID? {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return document.savedTemplates.first {
            $0.title.compare(title, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }?.id
    }

    func exportRoutineConfigYAML(templateID: UUID) throws -> String {
        guard let routine = savedTemplate(id: templateID) else {
            throw SamoyedCoreError.missingSavedTemplate(templateID)
        }

        let previewPlan = try TemplateEngine.previewDayPlan(from: routine)
        return try SamoyedPortableDayBlocks.exportYAML(from: previewPlan)
    }

    private func blockTemplates(from blocks: [TimeBlock]) -> [BlockTemplate] {
        blocks
            .filter { !$0.isCancelled && !$0.isBlankBaseBlock }
            .sorted(by: routineImportSort)
            .map { block in
                BlockTemplate(
                    id: block.id,
                    parentTemplateBlockID: block.parentBlockID,
                    layerIndex: block.layerIndex,
                    title: block.title,
                    note: block.note,
                    reminders: block.reminders,
                    taskBlueprints: block.tasks
                        .sorted {
                            if $0.order != $1.order {
                                return $0.order < $1.order
                            }
                            return $0.id.uuidString < $1.id.uuidString
                        }
                        .map { task in
                            TaskBlueprint(
                                id: task.id,
                                title: task.title,
                                order: task.order
                            )
                        },
                    timing: block.timing
                )
            }
    }

    private func routineImportSort(_ lhs: TimeBlock, _ rhs: TimeBlock) -> Bool {
        if lhs.layerIndex != rhs.layerIndex {
            return lhs.layerIndex < rhs.layerIndex
        }

        let lhsStart = lhs.resolvedStartMinuteOfDay ?? timingSortStart(lhs.timing)
        let rhsStart = rhs.resolvedStartMinuteOfDay ?? timingSortStart(rhs.timing)
        if lhsStart != rhsStart {
            return lhsStart < rhsStart
        }

        return lhs.id.uuidString < rhs.id.uuidString
    }

    private func timingSortStart(_ timing: TimeBlockTiming) -> Int {
        switch timing {
        case let .absolute(startMinuteOfDay, _):
            return startMinuteOfDay
        case let .relative(startOffsetMinutes, _):
            return startOffsetMinutes
        }
    }

    // MARK: Commands

    func activateStarterRoutine(
        assignedWeekdays: Set<Weekday>,
        today: LocalDay = .today(),
        startedAt: Date = .now
    ) throws {
        do {
            guard !assignedWeekdays.isEmpty else {
                throw SamoyedCoreError.emptyActivationWeekdays
            }
            let template = try StarterRoutineFactory.makeRoutine(createdAt: startedAt)
            let outcome = try documentRepository.mutate { current in
                current = try TemplateEngine.activate(
                    document: current,
                    template: template,
                    assignedWeekdays: assignedWeekdays,
                    today: today,
                    activatedAt: startedAt
                )
            }
            document = outcome.document
            selectedDate = today
            selectedTab = .now
            selectedBlockID = nil
            bootstrapState = .ready
            isLoaded = true
            documentDidChange()
            recordValidationEvent(
                .activationCompleted,
                outcome: "saved",
                variant: "workday-starter",
                durationMilliseconds: Int(Date.now.timeIntervalSince(startedAt) * 1_000)
            )
        } catch {
            recordValidationEvent(
                .activationFailed,
                outcome: "failed",
                variant: "workday-starter",
                durationMilliseconds: Int(Date.now.timeIntervalSince(startedAt) * 1_000)
            )
            throw error
        }
    }

    @discardableResult
    func saveFeedback(
        target: FeedbackTarget,
        on day: LocalDay,
        sentiment: FeedbackSentiment?,
        note: String,
        source: FeedbackSource
    ) throws -> FeedbackEvent {
        let saved = try feedbackService.save(
            FeedbackEvent(
                target: target,
                localDay: day,
                sentiment: sentiment,
                note: note,
                source: source
            )
        )
        try reloadAfterServiceMutation()
        return saved
    }

    func importSuggestion(version: Int, payload: String) throws {
        _ = try suggestionService.importSuggestion(version: version, payload: payload)
        try reloadAfterServiceMutation()
        openLibrary(destination: .suggestions)
    }

    func acceptSuggestion(
        _ suggestionID: UUID,
        allowReplacingExecutionState: Bool = false
    ) throws {
        _ = try suggestionService.accept(
            suggestionID,
            today: .today(),
            allowReplacingExecutionState: allowReplacingExecutionState
        )
        try reloadAfterServiceMutation()
    }

    func rejectSuggestion(_ suggestionID: UUID) throws {
        _ = try suggestionService.reject(suggestionID)
        try reloadAfterServiceMutation()
    }

    func assignRoutine(_ routineID: UUID?, to weekday: Weekday) throws {
        if let routineID, savedTemplate(id: routineID) == nil {
            throw SamoyedCoreError.missingSavedTemplate(routineID)
        }
        let outcome = try documentRepository.mutate { document in
            document.weekdayRules.removeAll { $0.weekday == weekday }
            if let routineID {
                document.weekdayRules.append(
                    WeekdayTemplateRule(weekday: weekday, savedTemplateID: routineID)
                )
                document.weekdayRules.sort { $0.weekday.rawValue < $1.weekday.rawValue }
            }
        }
        document = outcome.document
        documentDidChange()
    }

    func disconnectPlanner() {
        do {
            let outcome = try documentRepository.mutate { document in
                document.plannerSettings = PlannerSettings()
            }
            document = outcome.document
            documentDidChange()
        } catch {
            presentError(error)
        }
    }

    func completeTask(
        on date: LocalDay,
        blockID: UUID,
        taskID: UUID,
        completedAt: Date = .now
    ) throws -> TaskCompletionReference? {
        var plan = try materializedDayPlan(on: date)
        guard let blockIndex = plan.blocks.firstIndex(where: { $0.id == blockID }) else {
            throw SamoyedCoreError.missingBlock(blockID)
        }
        guard let taskIndex = plan.blocks[blockIndex].tasks.firstIndex(where: { $0.id == taskID }) else {
            return nil
        }
        guard !plan.blocks[blockIndex].tasks[taskIndex].isCompleted else {
            return nil
        }
        plan.blocks[blockIndex].tasks[taskIndex].isCompleted = true
        plan.blocks[blockIndex].tasks[taskIndex].completedAt = completedAt
        plan.hasUserEdits = true
        try commit(dayPlan: plan)
        recordValidationEvent(.checklistCompleted, outcome: "completed", variant: "now")
        return TaskCompletionReference(date: date, blockID: blockID, taskID: taskID)
    }

    func undoTaskCompletions(_ references: [TaskCompletionReference]) throws {
        guard let date = references.first?.date else { return }
        var plan = try materializedDayPlan(on: date)
        for reference in references where reference.date == date {
            guard let blockIndex = plan.blocks.firstIndex(where: { $0.id == reference.blockID }) else { continue }
            guard let taskIndex = plan.blocks[blockIndex].tasks.firstIndex(where: { $0.id == reference.taskID }) else { continue }
            plan.blocks[blockIndex].tasks[taskIndex].isCompleted = false
            plan.blocks[blockIndex].tasks[taskIndex].completedAt = nil
        }
        plan.hasUserEdits = true
        try commit(dayPlan: plan)
        recordValidationEvent(.checklistUndone, outcome: "restored", variant: "batch")
    }

    func recordNowVisible(at date: Date = .now) {
        let day = LocalDay(date: date)
        guard nowVisibleDays.insert(day).inserted else { return }
        recordValidationEvent(.nowVisible, outcome: "visible", at: date)
    }

    func recordValidationEvent(
        _ name: ValidationEventName,
        outcome: String? = nil,
        variant: String? = nil,
        durationMilliseconds: Int? = nil,
        at date: Date = .now
    ) {
        Task {
            await validationLogger.record(
                name,
                outcome: outcome,
                variant: variant,
                durationMilliseconds: durationMilliseconds,
                at: date
            )
        }
    }

    func validationExportURL() async -> URL? {
        await validationLogger.exportURL()
    }

    func clearValidationLog() async {
        await validationLogger.clear()
    }

    func toggleTask(on date: LocalDay, blockID: UUID, taskID: UUID) {
        // 这种“读 plan -> 改一处 -> 提交”的写法，是 store 里最常见的命令模式。
        mutateDayPlan(for: date) { plan in
            guard let blockIndex = plan.blocks.firstIndex(where: { $0.id == blockID }) else { return }
            guard let taskIndex = plan.blocks[blockIndex].tasks.firstIndex(where: { $0.id == taskID }) else { return }

            plan.blocks[blockIndex].tasks[taskIndex].isCompleted.toggle()
            plan.blocks[blockIndex].tasks[taskIndex].completedAt = plan.blocks[blockIndex].tasks[taskIndex].isCompleted ? Date() : nil
        }
    }

    func startCurrentBlockLiveActivity(referenceDate: Date = .now) {
        // 这里用 `Task` 启动异步工作，而不是阻塞主线程等待系统 API 返回。
        Task {
            guard #available(iOS 16.1, *) else { return }
            do {
                let outcome = try await SamoyedCurrentBlockLiveActivityController.start(
                    using: documentRepository,
                    at: referenceDate
                )
                if case let .unavailable(reason) = outcome {
                    presentErrorMessage(reason.userMessage)
                }
            } catch {
                presentError(error)
            }
        }
    }

    func endCurrentBlockLiveActivity() {
        Task {
            guard #available(iOS 16.1, *) else { return }
            await SamoyedCurrentBlockLiveActivityController.endAll()
        }
    }

    func syncCurrentBlockLiveActivity(referenceDate: Date = .now) {
        // “sync” 只刷新已经存在的 activity；创建始终留给显式的 start 操作。
        // 当前 block 不再匹配时会结束旧 activity，避免后台刷新意外创建系统界面。
        Task {
            guard #available(iOS 16.1, *) else { return }
            do {
                _ = try await SamoyedCurrentBlockLiveActivityController.sync(
                    using: documentRepository,
                    at: referenceDate
                )
            } catch {
                presentError(error)
            }
        }
    }

    func chooseTemplate(
        for date: LocalDay,
        templateID: UUID?,
        source: DayTemplateSelectionSource,
        forceReplace: Bool = false
    ) throws -> DayTemplateChoiceCommandResult {
        let outcome = try TemplateEngine.chooseTemplate(
            for: date,
            templateID: templateID,
            source: source,
            existingDayPlans: document.dayPlans,
            savedTemplates: document.savedTemplates,
            selectedAt: .now,
            forceReplace: forceReplace
        )

        switch outcome {
        case .requiresForceReplace:
            return .requiresConfirmation

        case let .applied(selection, dayPlan):
            document.daySelections.removeAll { $0.date == date }
            document.daySelections.append(selection)
            upsert(dayPlan: dayPlan)

            if selectedDate == date {
                selectedBlockID = nil
            }

            try persistDocument()
            return .applied
        }
    }

    private func mutateDayPlan(for date: LocalDay, mutation: (inout DayPlan) -> Void) {
        do {
            var plan = try materializedDayPlan(on: date)

            mutation(&plan)
            // 统一把“通过 store 命令产生的修改”记为用户编辑。
            plan.hasUserEdits = true
            try commit(dayPlan: plan)
        } catch {
            presentError(error)
        }
    }

    private func materializedDayPlan(on date: LocalDay) throws -> DayPlan {
        // 这个 helper 把“应该存在”的软约定提升为“若不存在就抛错”的硬约束。
        ensureMaterialized(for: date)
        guard let plan = document.dayPlan(for: date) else {
            throw SamoyedCoreError.missingDayPlanForDate(date)
        }
        return plan
    }

    private func commit(dayPlan: DayPlan) throws {
        // 所有写操作最终都应该收敛到这里，避免出现多个不同的持久化路径。
        upsert(dayPlan: dayPlan)
        try persistDocument()
    }

    private func upsert(dayPlan: DayPlan) {
        // `upsert = update or insert`，是数据库/存储层常见术语。
        if let index = document.dayPlans.firstIndex(where: { $0.date == dayPlan.date }) {
            document.dayPlans[index] = dayPlan
        } else {
            document.dayPlans.append(dayPlan)
            document.dayPlans.sort { $0.date < $1.date }
        }
    }

    private func persistDocument() throws {
        // 文档写盘后，统一走一个“文档已变更”钩子，刷新所有系统表面。
        try documentRepository.save(document)
        documentDidChange()
    }

    private func reloadAfterServiceMutation() throws {
        if let latest = try documentRepository.load() {
            document = latest
        }
        documentDidChange()
    }

    // MARK: Persistence & System Sync

    private func documentDidChange() {
        // The P0 app keeps the dormant widget projection fresh, but it does not
        // automatically start activities or schedule notifications.
        refreshVisualSystemSurfaces()
        syncCurrentBlockLiveActivity(
            referenceDate: SamoyedSimulationClock.adjusted(.now)
        )
    }

    private func refreshVisualSystemSurfaces() {
        WidgetCenter.shared.reloadTimelines(ofKind: SamoyedSharedConfig.widgetKind)
    }
}
