import Foundation

// 这个文件是 Widget 专用的“展示数据适配层”。
// 重要边界是：
// - `NowScreenModel` 仍然是 app 内部的屏幕模型
// - Widget 不直接依赖整个 View/Store，而是拿一个更扁平、更稳定的快照
// 对 C++ 开发者可以类比成：先把复杂业务对象投影成一个只读 DTO，
// 再交给另一个渲染进程使用。

// 单个任务在 Widget 中的扁平展示模型。
// 这里故意把 `UUID` 存成字符串，是因为 AppIntent/Widget 参数和跨进程通信
// 更适合使用稳定、易序列化的纯值数据。
struct SamoyedWidgetTaskItem: Identifiable, Equatable, Sendable {
    var dateISO: String
    var blockID: String
    var taskID: String
    var title: String
    var blockTitle: String
    var layerIndex: Int
    var isBlank: Bool
    var isCompleted: Bool
    var isCurrentBlock: Bool

    var id: String {
        taskID
    }
}

// 单个时间块在 Widget 中的展示模型。
// Widget UI 不需要知道完整的 `TimeBlock` 结构，只需要标题、层级、时间范围等。
struct SamoyedWidgetBlockItem: Identifiable, Equatable, Sendable {
    var blockID: String
    var title: String
    var layerIndex: Int
    var timeRangeText: String
    var endMinuteOfDay: Int? = nil
    var isBlank: Bool
    var hasIncompleteTasks: Bool
    var isCurrent: Bool

    var id: String {
        blockID
    }
}

enum SamoyedWidgetState: String, Equatable, Sendable {
    case active
    case caughtUp
    case needsSetup
    case unavailable
}

// Widget 的完整快照。
// 你可以把它理解为：“在某一时刻，Widget 需要拿到的全部只读数据包”。
// 一旦快照构建完成，Widget 视图层只负责渲染，不再做业务推理。
struct SamoyedWidgetSnapshot: Equatable, Sendable {
    var date: LocalDay
    var minuteOfDay: Int
    var state: SamoyedWidgetState
    var currentBlockTitle: String?
    var currentBlockTimeRangeText: String?
    var currentBlockNote: String? = nil
    var blocks: [SamoyedWidgetBlockItem]
    var remainingTaskCount: Int
    var tasks: [SamoyedWidgetTaskItem]
    var statusMessage: String?

    static func needsSetup(
        date: LocalDay,
        minuteOfDay: Int,
        message: String = "Choose today’s routine"
    ) -> SamoyedWidgetSnapshot {
        SamoyedWidgetSnapshot(
            date: date,
            minuteOfDay: minuteOfDay,
            state: .needsSetup,
            currentBlockTitle: nil,
            currentBlockTimeRangeText: nil,
            blocks: [],
            remainingTaskCount: 0,
            tasks: [],
            statusMessage: message
        )
    }

    static func unavailable(
        date: LocalDay,
        minuteOfDay: Int,
        message: String
    ) -> SamoyedWidgetSnapshot {
        SamoyedWidgetSnapshot(
            date: date,
            minuteOfDay: minuteOfDay,
            state: .unavailable,
            currentBlockTitle: nil,
            currentBlockTimeRangeText: nil,
            blocks: [],
            remainingTaskCount: 0,
            tasks: [],
            statusMessage: message
        )
    }

    static func placeholder() -> SamoyedWidgetSnapshot {
        // `placeholder` 是 WidgetKit 的占位内容：
        // 在系统还没拿到真实数据、或在配置页/预览页里，会先显示这份假数据。
        SamoyedWidgetSnapshot(
            date: LocalDay.today(),
            minuteOfDay: Date.now.minuteOfDay,
            state: .active,
            currentBlockTitle: "Now",
            currentBlockTimeRangeText: "09:00 - 10:30",
            currentBlockNote: "Finish the review while the decisions are fresh.",
            blocks: [
                SamoyedWidgetBlockItem(
                    blockID: UUID().uuidString,
                    title: "Focus Sprint",
                    layerIndex: 1,
                    timeRangeText: "09:00 - 10:30",
                    isBlank: false,
                    hasIncompleteTasks: true,
                    isCurrent: true
                ),
                SamoyedWidgetBlockItem(
                    blockID: UUID().uuidString,
                    title: "Morning",
                    layerIndex: 0,
                    timeRangeText: "08:00 - 12:00",
                    isBlank: false,
                    hasIncompleteTasks: true,
                    isCurrent: false
                )
            ],
            remainingTaskCount: 2,
            tasks: [
                SamoyedWidgetTaskItem(
                    dateISO: LocalDay.today().description,
                    blockID: UUID().uuidString,
                    taskID: UUID().uuidString,
                    title: "Finish the current task",
                    blockTitle: "Focus",
                    layerIndex: 1,
                    isBlank: false,
                    isCompleted: false,
                    isCurrentBlock: true
                ),
                SamoyedWidgetTaskItem(
                    dateISO: LocalDay.today().description,
                    blockID: UUID().uuidString,
                    taskID: UUID().uuidString,
                    title: "Prepare the next step",
                    blockTitle: "Focus",
                    layerIndex: 1,
                    isBlank: false,
                    isCompleted: false,
                    isCurrentBlock: true
                )
            ],
            statusMessage: nil
        )
    }
}

// `SnapshotBuilder` 负责把 app 的屏幕模型压缩成 widget 友好的结构。
// 这里不直接从 document 拼 UI，是因为：
// 1. 业务规则已经在 presentation 层算好了
// 2. widget 只需要少量字段，重新依赖完整模型会增加耦合
enum SamoyedWidgetSnapshotBuilder {
    static func makeSnapshot(
        from now: NowScreenModel,
        maxTaskCount: Int
    ) -> SamoyedWidgetSnapshot {
        if now.focusState == .noRoutine, !now.activeChain.contains(where: { !$0.isBlank }) {
            return .needsSetup(
                date: now.date,
                minuteOfDay: now.minuteOfDay,
                message: "Choose a routine to bring Now into focus."
            )
        }

        // 先把当前活跃链转换成轻量 block 列表。
        let blocks = now.activeChain.map { item in
            SamoyedWidgetBlockItem(
                blockID: item.id.uuidString,
                title: item.title,
                layerIndex: item.layerIndex,
                timeRangeText: formattedTimeRange(
                    startMinuteOfDay: item.startMinuteOfDay,
                    endMinuteOfDay: item.endMinuteOfDay
                ),
                endMinuteOfDay: item.endMinuteOfDay,
                isBlank: item.isBlank,
                hasIncompleteTasks: item.hasIncompleteTasks,
                isCurrent: item.isCurrent
            )
        }
        // Widget 更关注“当前块”，所以如果链上有 current 就优先找它。
        let currentBlock = blocks.first(where: \.isCurrent) ?? blocks.first
        let currentBlockNote = currentBlock.flatMap { block in
            now.noteSections.first(where: { $0.id.uuidString == block.blockID })?.note
        }
        // 任务也会做一次优先级重排，让当前块的任务优先显示。
        let prioritizedSections = prioritizedTaskSections(from: now.taskSections)
        let tasks = prioritizedSections
            .flatMap { section in
                prioritizedTasks(from: section)
                    .filter { !$0.isCompleted }
                    .map { task in
                    SamoyedWidgetTaskItem(
                        dateISO: now.date.description,
                        blockID: section.id.uuidString,
                        taskID: task.id.uuidString,
                        title: task.title,
                        blockTitle: section.title,
                        layerIndex: section.layerIndex,
                        isBlank: false,
                        isCompleted: task.isCompleted,
                        isCurrentBlock: section.isCurrent
                    )
                    }
            }

        let remainingTaskCount = now.taskSections
            .flatMap(\.tasks)
            .filter { !$0.isCompleted }
            .count
        let state: SamoyedWidgetState
        if remainingTaskCount > 0 {
            state = .active
        } else if let currentBlock, !currentBlock.isBlank {
            state = .caughtUp
        } else {
            state = .unavailable
        }

        return SamoyedWidgetSnapshot(
            date: now.date,
            minuteOfDay: now.minuteOfDay,
            state: state,
            currentBlockTitle: currentBlock?.title,
            currentBlockTimeRangeText: currentBlock?.timeRangeText,
            currentBlockNote: currentBlockNote,
            blocks: blocks,
            remainingTaskCount: remainingTaskCount,
            tasks: Array(tasks.prefix(max(0, maxTaskCount))),
            statusMessage: state == .unavailable
                ? (now.statusMessage ?? "Nothing is active right now.")
                : nil
        )
    }

    static func nextRefreshDate(
        for snapshot: SamoyedWidgetSnapshot,
        referenceDate: Date
    ) -> Date {
        // Widget 不能像 app 内部那样持续运行，所以要显式告诉系统：
        // “最晚什么时候请再来拿一次新快照”。
        // 这里选择“当前块结束时”或“15 分钟后”中的更早者，保证时间推进时 UI 不会太旧。
        let fallback = referenceDate.addingTimeInterval(15 * 60)

        guard
            let currentBlock = snapshot.blocks.first(where: \.isCurrent) ?? snapshot.blocks.first,
            let endMinuteOfDay = currentBlock.endMinuteOfDay,
            let boundary = snapshot.date.date(minuteOfDay: endMinuteOfDay)
        else {
            return fallback
        }

        return min(boundary, fallback)
    }

    private static func prioritizedTaskSections(
        from sections: [NowTaskSection]
    ) -> [NowTaskSection] {
        // 当前 section 优先，这样小组件有限的空间会先展示“你现在最该做什么”。
        if let taskSourceSection = sections.first(where: \.isTaskSource) {
            return [taskSourceSection] + sections.filter { $0.id != taskSourceSection.id }
        }

        guard let currentSection = sections.first(where: \.isCurrent) else {
            return sections
        }

        return [currentSection] + sections.filter { $0.id != currentSection.id }
    }

    private static func prioritizedTasks(
        from section: NowTaskSection
    ) -> [TaskItem] {
        section.tasks.enumerated()
            .sorted { lhs, rhs in
                if lhs.element.isCompleted != rhs.element.isCompleted {
                    return !lhs.element.isCompleted
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    private static func formattedTimeRange(
        startMinuteOfDay: Int,
        endMinuteOfDay: Int
    ) -> String {
        // Widget 展示层偏向直接使用字符串，避免每个视图再去重复格式化。
        "\(formattedTime(startMinuteOfDay)) - \(formattedTime(endMinuteOfDay))"
    }

    private static func formattedTime(_ minuteOfDay: Int) -> String {
        let hour = minuteOfDay / 60
        let minute = minuteOfDay % 60
        return String(format: "%02d:%02d", hour, minute)
    }

}

extension SamoyedDocumentRepository {
    func widgetSnapshot(
        at date: Date,
        maxTaskCount: Int
    ) throws -> SamoyedWidgetSnapshot {
        let localDay = LocalDay(date: date)
        guard let persistedDocument = try load() else {
            return .needsSetup(date: localDay, minuteOfDay: date.minuteOfDay)
        }
        if persistedDocument.isEmptyForActivation {
            return .needsSetup(date: localDay, minuteOfDay: date.minuteOfDay)
        }
        let document = try preparedDocument(at: date)

        // repository 先提供“准备好的 now screen model”，
        // 再由 builder 生成 widget 快照。
        // 这样 repository 负责读数据和准备业务上下文，builder 负责展示投影。
        let now = try SamoyedPresentation.nowScreenModel(
            document: document,
            date: localDay,
            minuteOfDay: date.minuteOfDay
        )
        return SamoyedWidgetSnapshotBuilder.makeSnapshot(
            from: now,
            maxTaskCount: maxTaskCount
        )
    }
}
