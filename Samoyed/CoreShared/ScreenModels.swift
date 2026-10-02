import Foundation

// 这是“presentation layer（展示映射层）”。
//
// 核心思想非常重要：
// - `Models.swift` 里的类型代表业务真相
// - `ScreenModels.swift` 里的类型代表“某个页面此刻想显示什么”
//
// 两者不应该混在一起，原因是：
// 1. UI 经常需要额外字段（如高亮、排序、初始滚动位置）
// 2. 这些字段不适合反向污染业务模型
// 3. 展示映射独立后，页面测试和纯逻辑测试都更容易做

// `Now` 页面的链路展示项。
// 它不一定是 document 里的原始 block，而是被 presentation 层整理后的结果。
public struct NowChainItem: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var layerIndex: Int
    public var startMinuteOfDay: Int
    public var endMinuteOfDay: Int
    public var isBlank: Bool
    public var hasIncompleteTasks: Bool
    public var isCurrent: Bool
}

public struct NowNoteSection: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var layerIndex: Int
    public var note: String
    public var isBlank: Bool
    public var isCurrent: Bool
}

public struct NowTaskSection: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var layerIndex: Int
    public var startMinuteOfDay: Int
    public var endMinuteOfDay: Int
    public var tasks: [TaskItem]
    public var isCurrent: Bool
    public var isTaskSource: Bool
    public var isComplete: Bool
}

public enum NowFocusState: String, Equatable, Sendable {
    case noRoutine
    case beforeFirstBlock
    case openTime
    case active
    case finished
}

public struct NowFocusBlock: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var note: String?
    public var startMinuteOfDay: Int
    public var endMinuteOfDay: Int
    public var taskSourceBlockID: UUID?
    public var taskSourceTitle: String?
    public var visibleTasks: [TaskItem]
    public var remainingTaskCount: Int
}

public struct NowUpcomingBlock: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var transitionMinuteOfDay: Int
}

public struct NowScreenModel: Equatable, Sendable {
    public var date: LocalDay
    public var minuteOfDay: Int
    public var activeChain: [NowChainItem]
    public var currentBlockTitle: String?
    public var noteSections: [NowNoteSection]
    public var statusMessage: String?
    public var taskSourceTitle: String?
    public var taskSections: [NowTaskSection]
    public var focusState: NowFocusState = .noRoutine
    public var focusBlock: NowFocusBlock?
    public var upcomingBlock: NowUpcomingBlock?
}

// `Today` 页面会同时展示：
// - 时间轴上的 block
// - 空白时段 open slot
// - 当前选中 block 详情
// - 用户当前可添加的 block 类型
public struct TimelineBlockItem: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var parentBlockID: UUID?
    public var title: String
    public var note: String?
    public var startMinuteOfDay: Int
    public var endMinuteOfDay: Int
    public var layerIndex: Int
    public var isBlank: Bool
    public var incompleteTaskCount: Int
}

public struct TodayOpenSlotItem: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var startMinuteOfDay: Int
    public var endMinuteOfDay: Int

    public var durationMinutes: Int {
        endMinuteOfDay - startMinuteOfDay
    }
}

public enum TodayAddOptionKind: Equatable, Sendable {
    case base
    case overlay(parentBlockID: UUID, layerIndex: Int)
}

public struct TodayAddOption: Identifiable, Equatable, Sendable {
    public var title: String
    public var kind: TodayAddOptionKind

    public var id: String {
        switch kind {
        case .base:
            return "base"
        case let .overlay(parentBlockID, layerIndex):
            return "overlay-\(parentBlockID.uuidString)-\(layerIndex)"
        }
    }
}

public struct BlockDetailModel: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var note: String?
    public var layerIndex: Int
    public var startMinuteOfDay: Int
    public var endMinuteOfDay: Int
    public var isBlank: Bool
    public var reminders: [ReminderRule]
    public var tasks: [TaskItem]
    public var parentBlockID: UUID?
    public var parentBlockTitle: String?
}

public struct TodayScreenModel: Equatable, Sendable {
    public var date: LocalDay
    public var blocks: [TimelineBlockItem]
    public var openSlots: [TodayOpenSlotItem]
    public var addOptions: [TodayAddOption]
    public var selectedBlock: BlockDetailModel?
    public var initialScrollMinute: Int
    public var initialFocusBlockID: UUID?
}

// `Templates` 页面关心的是“模板摘要”和“今天/明天的调度结果”，
// 而不是整份模板的全部底层字段。
public struct SuggestedTemplateSummary: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var sourceDate: LocalDay
    public var timeRangeText: String?
    public var baseBlockCount: Int
    public var overlayCount: Int
    public var totalBlockCount: Int
    public var taskBlueprintCount: Int
    public var reminderCount: Int
    public var previewTitles: [String]
}

public struct TemplateCandidateSummary: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var timeRangeText: String?
    public var baseBlockCount: Int
    public var overlayCount: Int
    public var totalBlockCount: Int
    public var taskCount: Int
    public var reminderCount: Int
    public var previewTitles: [String]
    public var assignedWeekdays: [Weekday]
    public var isDefaultForToday: Bool
    public var isCurrentForToday: Bool
}

public struct TemplateScheduleSummary: Equatable, Sendable {
    public var date: LocalDay
    public var weekday: Weekday
    public var weekdayTemplateID: UUID?
    public var weekdayTemplateTitle: String?
    public var overrideTemplateID: UUID?
    public var overrideTemplateTitle: String?
    public var finalTemplateID: UUID?
    public var finalTemplateTitle: String?
}

public struct DayTemplateChooserModel: Equatable, Sendable {
    public var date: LocalDay
    public var currentSelection: TemplateCandidateSummary?
    public var defaultTemplate: TemplateCandidateSummary?
    public var availableTemplates: [TemplateCandidateSummary]
    public var requiresSelection: Bool
    public var canChooseNoTemplate: Bool
}

public struct TemplatesScreenModel: Equatable, Sendable {
    public var todayChooser: DayTemplateChooserModel
    public var suggestedTemplates: [SuggestedTemplateSummary]
    public var savedTemplates: [TemplateCandidateSummary]
    public var todaySchedule: TemplateScheduleSummary
    public var tomorrowSchedule: TemplateScheduleSummary
}

// `SamoyedPresentation` 是纯映射器：
// 输入 document + 当前上下文，输出屏幕模型。
// 它不写文件、不改 document，也不接触 SwiftUI 组件。
public enum SamoyedPresentation {
    public static func nowScreenModel(
        document: SamoyedDocument,
        date: LocalDay,
        minuteOfDay: Int
    ) throws -> NowScreenModel {
        // `Now` 页面本质上是在问：
        // “某一天的某一分钟，当前激活链(active chain)是什么？”
        let plan = try DayPlanEngine.resolved(document.dayPlan(for: date) ?? DayPlan(date: date))
        let selection = try DayPlanEngine.activeSelection(in: plan, at: minuteOfDay)
        let sortedChain = selection.chain.sorted(by: nowChainSort)

        let activeChain = makeNowChainItems(
            from: sortedChain,
            activeBlockID: selection.activeBlock?.id
        )
        let noteSections = makeNowNoteSections(
            from: sortedChain,
            activeBlockID: selection.activeBlock?.id
        )
        let taskSections = makeNowTaskSections(
            from: sortedChain,
            activeBlockID: selection.activeBlock?.id,
            taskSourceBlockID: selection.taskSourceBlock?.id
        )

        let userBlocks = plan.blocks.filter { !$0.isCancelled && !$0.isBlankBaseBlock }
        let activeUserBlock = selection.activeBlock?.isBlankBaseBlock == false ? selection.activeBlock : nil
        let taskSourceTasks = selection.taskSourceBlock?.tasks
            .filter { !$0.isCompleted }
            .sorted(by: taskSort) ?? []
        let upcoming = try DayPlanEngine.upcomingActiveBlock(in: plan, after: minuteOfDay)

        let focusState: NowFocusState
        if userBlocks.isEmpty {
            focusState = .noRoutine
        } else if activeUserBlock != nil {
            focusState = .active
        } else if let firstStart = userBlocks.compactMap(\.resolvedStartMinuteOfDay).min(), minuteOfDay < firstStart {
            focusState = .beforeFirstBlock
        } else if upcoming != nil {
            focusState = .openTime
        } else {
            focusState = .finished
        }

        let focusBlock = activeUserBlock.flatMap { block -> NowFocusBlock? in
            guard
                let start = block.resolvedStartMinuteOfDay,
                let end = block.resolvedEndMinuteOfDay
            else {
                return nil
            }
            return NowFocusBlock(
                id: block.id,
                title: block.title,
                note: block.note,
                startMinuteOfDay: start,
                endMinuteOfDay: end,
                taskSourceBlockID: selection.taskSourceBlock?.id,
                taskSourceTitle: selection.taskSourceBlock?.title,
                visibleTasks: Array(taskSourceTasks.prefix(3)),
                remainingTaskCount: taskSourceTasks.count
            )
        }
        let upcomingBlock = upcoming.map {
            NowUpcomingBlock(
                id: $0.block.id,
                title: $0.block.title,
                transitionMinuteOfDay: $0.transitionMinuteOfDay
            )
        }

        let statusMessage: String?
        if !taskSections.isEmpty {
            // 有任务时，任务区自己就已经表达状态，不再额外显示文案。
            statusMessage = nil
        } else if selection.activeBlock?.isBlankBaseBlock == true {
            statusMessage = "You're in open time right now."
        } else if selection.activeBlock != nil {
            statusMessage = "No incomplete tasks in this chain."
        } else {
            statusMessage = "No plan for today yet."
        }

        return NowScreenModel(
            date: date,
            minuteOfDay: minuteOfDay,
            activeChain: activeChain,
            currentBlockTitle: selection.activeBlock?.isBlankBaseBlock == true ? nil : selection.activeBlock?.title,
            noteSections: noteSections,
            statusMessage: statusMessage,
            taskSourceTitle: selection.taskSourceBlock?.title,
            taskSections: taskSections,
            focusState: focusState,
            focusBlock: focusBlock,
            upcomingBlock: upcomingBlock
        )
    }

    public static func todayScreenModel(
        document: SamoyedDocument,
        date: LocalDay,
        selectedBlockID: UUID?,
        currentMinute: Int?
    ) throws -> TodayScreenModel {
        // `Today` 页比 `Now` 更复杂：
        // 它需要运行时 blank block 来推导 open slots，但真正展示的时间轴仍只画用户 block。
        let runtimePlan = try DayPlanEngine.runtimeResolved(document.dayPlan(for: date) ?? DayPlan(date: date))
        let openSlots = runtimePlan.blocks
            .filter { !$0.isCancelled && $0.isBlankBaseBlock }
            .compactMap { block -> TodayOpenSlotItem? in
                guard
                    let start = block.resolvedStartMinuteOfDay,
                    let end = block.resolvedEndMinuteOfDay
                else {
                    return nil
                }

                return TodayOpenSlotItem(
                    id: block.id,
                    startMinuteOfDay: start,
                    endMinuteOfDay: end
                )
            }
            .sorted { lhs, rhs in
                // 统一按照时间顺序排序，避免 UI 层自己再做二次整理。
                if lhs.startMinuteOfDay != rhs.startMinuteOfDay {
                    return lhs.startMinuteOfDay < rhs.startMinuteOfDay
                }
                return lhs.endMinuteOfDay < rhs.endMinuteOfDay
            }
        let sortedBlocks = runtimePlan.blocks
            .filter { !$0.isCancelled && !$0.isBlankBaseBlock }
            .compactMap { block -> TimelineBlockItem? in
                guard
                    let start = block.resolvedStartMinuteOfDay,
                    let end = block.resolvedEndMinuteOfDay
                else {
                    return nil
                }

                let snappedStart = start.snapped(toStep: 5, within: 0 ... (24 * 60 - 5))
                let snappedEnd = end.snapped(
                    toStep: 5,
                    within: min(snappedStart + 5, 24 * 60) ... (24 * 60)
                )

                return TimelineBlockItem(
                    id: block.id,
                    parentBlockID: block.parentBlockID,
                    title: block.title,
                    note: block.note,
                    startMinuteOfDay: snappedStart,
                    endMinuteOfDay: snappedEnd,
                    layerIndex: block.layerIndex,
                    isBlank: false,
                    incompleteTaskCount: block.tasks.filter { !$0.isCompleted }.count
                )
            }
            .sorted(by: timelineSort)

        let addOptions = makeTodayAddOptions(
            selectedBlockID: selectedBlockID,
            blocks: runtimePlan.blocks
        )

        // Focus selection is a presentation decision:
        // explicit user selection wins; if we're on "today now", prefer the current
        // active *user* block; otherwise fall back to the first real block.
        let visibleBlockIDs = Set(sortedBlocks.map(\.id))
        let focusedBlockID: UUID?
        if let selectedBlockID, visibleBlockIDs.contains(selectedBlockID) {
            focusedBlockID = selectedBlockID
        } else if let currentMinute {
            let selection = try DayPlanEngine.activeSelection(
                in: document.dayPlan(for: date) ?? DayPlan(date: date),
                at: currentMinute
            )
            focusedBlockID = selection.chain.reversed().first(where: { !$0.isBlankBaseBlock })?.id
        } else {
            focusedBlockID = sortedBlocks.first?.id
        }

        let selectedBlock = runtimePlan.blocks
            .first(where: { $0.id == focusedBlockID && !$0.isCancelled && !$0.isBlankBaseBlock })
            .flatMap { detailModel(for: $0, allBlocks: runtimePlan.blocks) }

        let fallbackMinute = sortedBlocks.first(where: { $0.id == focusedBlockID })?.startMinuteOfDay
            ?? currentMinute
            ?? sortedBlocks.first?.startMinuteOfDay
            ?? 0

        return TodayScreenModel(
            date: date,
            blocks: sortedBlocks,
            openSlots: openSlots,
            addOptions: addOptions,
            selectedBlock: selectedBlock,
            initialScrollMinute: fallbackMinute,
            initialFocusBlockID: focusedBlockID
        )
    }

    public static func templatesScreenModel(
        document: SamoyedDocument,
        referenceDay: LocalDay
    ) throws -> TemplatesScreenModel {
        let suggested = try TemplateEngine.suggestedTemplates(
            referenceDay: referenceDay,
            from: document.dayPlans
        )
        .map { template in
            let metrics = try templateMetrics(for: template.blocks)
            return SuggestedTemplateSummary(
                id: template.id,
                sourceDate: template.sourceDate,
                timeRangeText: metrics.timeRangeText,
                baseBlockCount: template.blocks.filter { $0.layerIndex == 0 }.count,
                overlayCount: template.blocks.filter { $0.layerIndex > 0 }.count,
                totalBlockCount: template.blocks.count,
                taskBlueprintCount: template.blocks.reduce(0) { $0 + $1.taskBlueprints.count },
                reminderCount: template.blocks.reduce(0) { $0 + $1.reminders.count },
                previewTitles: metrics.previewTitles
            )
        }

        let defaultTemplateID = document.weekdayRules
            .first(where: { $0.weekday == referenceDay.weekday })?
            .savedTemplateID
        // A date rule may change while its executed plan keeps the original snapshot.
        // Describe the plan that Today actually displays, including an unsourced plan.
        let currentTemplateID: UUID?
        if let plan = document.dayPlan(for: referenceDay) {
            currentTemplateID = plan.sourceSavedTemplateID
        } else {
            currentTemplateID = document.daySelection(for: referenceDay)?.selectedTemplateID
        }

        let saved: [TemplateCandidateSummary] = try document.savedTemplates.map { template in
            let metrics = try templateMetrics(for: template.blocks)
            return TemplateCandidateSummary(
                id: template.id,
                title: template.title,
                timeRangeText: metrics.timeRangeText,
                baseBlockCount: template.blocks.filter { $0.layerIndex == 0 }.count,
                overlayCount: template.blocks.filter { $0.layerIndex > 0 }.count,
                totalBlockCount: template.blocks.count,
                taskCount: template.blocks.reduce(0) { $0 + $1.taskBlueprints.count },
                reminderCount: template.blocks.reduce(0) { $0 + $1.reminders.count },
                previewTitles: metrics.previewTitles,
                assignedWeekdays: document.weekdayRules
                    .filter { $0.savedTemplateID == template.id }
                    .map(\.weekday)
                    .sorted(by: { $0.rawValue < $1.rawValue }),
                isDefaultForToday: template.id == defaultTemplateID,
                isCurrentForToday: template.id == currentTemplateID
            )
        }
        .sorted { lhs, rhs in
            lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }

        return TemplatesScreenModel(
            todayChooser: DayTemplateChooserModel(
                date: referenceDay,
                currentSelection: currentTemplateID.flatMap { currentID in
                    saved.first(where: { $0.id == currentID })
                },
                defaultTemplate: defaultTemplateID.flatMap { defaultID in
                    saved.first(where: { $0.id == defaultID })
                },
                availableTemplates: saved,
                requiresSelection: try TemplateEngine.requiresExplicitTemplateSelection(
                    for: referenceDay,
                    today: referenceDay,
                    existingDayPlans: document.dayPlans,
                    daySelections: document.daySelections
                ),
                canChooseNoTemplate: true
            ),
            suggestedTemplates: suggested,
            savedTemplates: saved,
            todaySchedule: try scheduleSummary(for: referenceDay, document: document),
            tomorrowSchedule: try scheduleSummary(for: referenceDay.adding(days: 1), document: document)
        )
    }

    private static func scheduleSummary(
        for date: LocalDay,
        document: SamoyedDocument
    ) throws -> TemplateScheduleSummary {
        let selectedTemplate = try TemplateEngine.selectedSavedTemplate(
            for: date,
            savedTemplates: document.savedTemplates,
            weekdayRules: document.weekdayRules,
            overrides: document.overrides,
            daySelections: document.daySelections
        )

        let weekdayTemplateID = document.weekdayRules.first(where: { $0.weekday == date.weekday })?.savedTemplateID
        let weekdayTemplateTitle = document.savedTemplates.first(where: { $0.id == weekdayTemplateID })?.title
        let overrideTemplateID = document.overrides.first(where: { $0.date == date })?.savedTemplateID
        let overrideTemplateTitle = document.savedTemplates.first(where: { $0.id == overrideTemplateID })?.title

        return TemplateScheduleSummary(
            date: date,
            weekday: date.weekday,
            weekdayTemplateID: weekdayTemplateID,
            weekdayTemplateTitle: weekdayTemplateTitle,
            overrideTemplateID: overrideTemplateID,
            overrideTemplateTitle: overrideTemplateTitle,
            finalTemplateID: selectedTemplate?.id,
            finalTemplateTitle: selectedTemplate?.title
        )
    }

    private nonisolated static func detailModel(for block: TimeBlock, allBlocks: [TimeBlock]) -> BlockDetailModel? {
        // Views consume this richer display model so they do not need to know how to
        // find parent titles, snap times, or sort tasks themselves.
        guard
            !block.isBlankBaseBlock,
            let start = block.resolvedStartMinuteOfDay,
            let end = block.resolvedEndMinuteOfDay
        else {
            return nil
        }

        let snappedStart = start.snapped(toStep: 5, within: 0 ... (24 * 60 - 5))
        let snappedEnd = end.snapped(
            toStep: 5,
            within: min(snappedStart + 5, 24 * 60) ... (24 * 60)
        )

        let parentTitle = block.parentBlockID.flatMap { parentID in
            allBlocks.first(where: { $0.id == parentID })?.title
        }

        return BlockDetailModel(
            id: block.id,
            title: block.title,
            note: block.note,
            layerIndex: block.layerIndex,
            startMinuteOfDay: snappedStart,
            endMinuteOfDay: snappedEnd,
            isBlank: false,
            reminders: block.reminders,
            tasks: block.tasks.sorted(by: taskSort),
            parentBlockID: block.parentBlockID,
            parentBlockTitle: parentTitle
        )
    }
}

private nonisolated func makeTodayAddOptions(
    selectedBlockID: UUID?,
    blocks: [TimeBlock]
) -> [TodayAddOption] {
    var options = [
        TodayAddOption(
            title: "New Block",
            kind: .base
        )
    ]

    guard let selectedBlockID else {
        return options
    }

    let selectableBlocks = blocks.filter { !$0.isCancelled && !$0.isBlankBaseBlock }
    let blocksByID = Dictionary(uniqueKeysWithValues: selectableBlocks.map { ($0.id, $0) })
    guard let selectedBlock = blocksByID[selectedBlockID] else {
        return options
    }

    var path: [TimeBlock] = []
    var cursor: TimeBlock? = selectedBlock

    while let block = cursor {
        path.append(block)
        cursor = block.parentBlockID.flatMap { blocksByID[$0] }
    }

    options.append(
        contentsOf: path.reversed().map { block in
            TodayAddOption(
                title: "New \(nextTimelineLayerTitle(after: block.layerIndex)) in \(block.title)",
                kind: .overlay(
                    parentBlockID: block.id,
                    layerIndex: block.layerIndex + 1
                )
            )
        }
    )

    return options
}

private nonisolated func nextTimelineLayerTitle(after layerIndex: Int) -> String {
    _ = layerIndex
    return "Overlay"
}

private nonisolated func makeNowChainItems(
    from chain: [TimeBlock],
    activeBlockID: UUID?
) -> [NowChainItem] {
    // `nonisolated` here means this helper is just a pure mapper with no actor-bound state.
    chain.compactMap { block in
        guard
            let start = block.resolvedStartMinuteOfDay,
            let end = block.resolvedEndMinuteOfDay
        else {
            return nil
        }

        return NowChainItem(
            id: block.id,
            title: block.title,
            layerIndex: block.layerIndex,
            startMinuteOfDay: start,
            endMinuteOfDay: end,
            isBlank: block.isBlankBaseBlock,
            hasIncompleteTasks: block.hasIncompleteTasks,
            isCurrent: block.id == activeBlockID
        )
    }
}

private nonisolated func makeNowNoteSections(
    from chain: [TimeBlock],
    activeBlockID: UUID?
) -> [NowNoteSection] {
    // Notes become their own UI sections even though they originate from the same blocks.
    chain.compactMap { block in
        guard let note = normalizedNoteText(block.note) else {
            return nil
        }

        return NowNoteSection(
            id: block.id,
            title: block.title,
            layerIndex: block.layerIndex,
            note: note,
            isBlank: block.isBlankBaseBlock,
            isCurrent: block.id == activeBlockID
        )
    }
}

private nonisolated func makeNowTaskSections(
    from chain: [TimeBlock],
    activeBlockID: UUID?,
    taskSourceBlockID: UUID?
) -> [NowTaskSection] {
    // Empty task lists simply do not appear in the Now tasks area.
    chain.filter { !$0.tasks.isEmpty }.compactMap { block in
        makeNowTaskSection(
            from: block,
            activeBlockID: activeBlockID,
            taskSourceBlockID: taskSourceBlockID
        )
    }
}

private nonisolated func makeNowTaskSection(
    from block: TimeBlock,
    activeBlockID: UUID?,
    taskSourceBlockID: UUID?
) -> NowTaskSection? {
    guard
        let start = block.resolvedStartMinuteOfDay,
        let end = block.resolvedEndMinuteOfDay
    else {
        return nil
    }

    return NowTaskSection(
        id: block.id,
        title: block.title,
        layerIndex: block.layerIndex,
        startMinuteOfDay: start,
        endMinuteOfDay: end,
        tasks: block.tasks.sorted(by: taskSort),
        isCurrent: block.id == activeBlockID,
        isTaskSource: block.id == taskSourceBlockID,
        isComplete: !block.hasIncompleteTasks
    )
}

private nonisolated func templateMetrics(
    for blocks: [BlockTemplate]
) throws -> (timeRangeText: String?, previewTitles: [String]) {
    let template = SavedDayTemplate(
        title: "Preview",
        sourceSuggestedTemplateID: UUID(),
        blocks: blocks
    )
    let preview = try TemplateEngine.previewDayPlan(from: template)
    let visibleBlocks = preview.blocks
        .filter { !$0.isCancelled }
        .sorted { lhs, rhs in
            let lhsStart = lhs.resolvedStartMinuteOfDay ?? Int.max
            let rhsStart = rhs.resolvedStartMinuteOfDay ?? Int.max
            if lhsStart != rhsStart {
                return lhsStart < rhsStart
            }
            if lhs.layerIndex != rhs.layerIndex {
                return lhs.layerIndex < rhs.layerIndex
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    let startMinute = visibleBlocks.compactMap(\.resolvedStartMinuteOfDay).min()
    let endMinute = visibleBlocks.compactMap(\.resolvedEndMinuteOfDay).max()
    let timeRangeText: String? = if let startMinute, let endMinute {
        "\(formattedMinute(startMinute)) - \(formattedMinute(endMinute))"
    } else {
        nil
    }
    let previewTitles = Array(
        visibleBlocks
            .filter { $0.layerIndex == 0 }
            .map(\.title)
            .prefix(3)
    )

    return (timeRangeText, previewTitles)
}

private nonisolated func formattedMinute(_ minuteOfDay: Int) -> String {
    let hour = minuteOfDay / 60
    let minute = minuteOfDay % 60
    return String(format: "%02d:%02d", hour, minute)
}

private nonisolated func normalizedNoteText(_ note: String?) -> String? {
    // Domain models often allow nil and empty-string separately; the UI usually does not care.
    guard let note else {
        return nil
    }

    let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private nonisolated func taskSort(_ lhs: TaskItem, _ rhs: TaskItem) -> Bool {
    // Explicit user order wins; UUID only provides a stable tie-breaker.
    if lhs.order != rhs.order {
        return lhs.order < rhs.order
    }
    return lhs.id.uuidString < rhs.id.uuidString
}

private nonisolated func nowChainSort(_ lhs: TimeBlock, _ rhs: TimeBlock) -> Bool {
    // Higher layer first matches the Now screen's "top overlay is most important" rule.
    if lhs.layerIndex != rhs.layerIndex {
        return lhs.layerIndex > rhs.layerIndex
    }

    if lhs.resolvedStartMinuteOfDay != rhs.resolvedStartMinuteOfDay {
        return (lhs.resolvedStartMinuteOfDay ?? 0) < (rhs.resolvedStartMinuteOfDay ?? 0)
    }

    return lhs.id.uuidString < rhs.id.uuidString
}

private nonisolated func timelineSort(_ lhs: TimelineBlockItem, _ rhs: TimelineBlockItem) -> Bool {
    // Today is visually a timeline, so chronological order dominates the sort.
    if lhs.startMinuteOfDay != rhs.startMinuteOfDay {
        return lhs.startMinuteOfDay < rhs.startMinuteOfDay
    }
    if lhs.layerIndex != rhs.layerIndex {
        return lhs.layerIndex < rhs.layerIndex
    }
    return lhs.id.uuidString < rhs.id.uuidString
}
