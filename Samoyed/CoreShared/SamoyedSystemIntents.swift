#if canImport(ActivityKit) && canImport(AppIntents) && canImport(WidgetKit) && !os(macOS)
import ActivityKit
import AppIntents
import Foundation
import WidgetKit

struct SetWidgetTaskCompletionIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Task Completion"
    static let description = IntentDescription("Update a checklist item directly from the Samoyed widget.")
    static let openAppWhenRun = false
    static let isDiscoverable = false

    @Parameter(title: "Date ISO")
    var dateISO: String

    @Parameter(title: "Block ID")
    var blockID: String

    @Parameter(title: "Task ID")
    var taskID: String

    @Parameter(title: "Completed")
    var isCompleted: Bool

    init() {}

    init(
        dateISO: String,
        blockID: String,
        taskID: String,
        isCompleted: Bool
    ) {
        self.dateISO = dateISO
        self.blockID = blockID
        self.taskID = taskID
        self.isCompleted = isCompleted
    }

    func perform() async throws -> some IntentResult {
        // Production widget actions are completion-only. Ignore a stale or
        // hand-authored intent payload that attempts to reopen a task.
        guard isCompleted else {
            return .result()
        }

        guard
            let localDay = LocalDay(isoDateString: dateISO),
            let blockUUID = UUID(uuidString: blockID),
            let taskUUID = UUID(uuidString: taskID)
        else {
            return .result()
        }

        let repository = SamoyedDocumentRepository.widgetLive
        _ = try SamoyedWidgetTaskAction.setCompletion(
            on: localDay,
            blockID: blockUUID,
            taskID: taskUUID,
            isCompleted: true,
            repository: repository
        )

        WidgetCenter.shared.reloadTimelines(ofKind: SamoyedSharedConfig.widgetKind)
        _ = try await SamoyedCurrentBlockLiveActivityController.sync(
            using: repository,
            at: .now
        )
        return .result()
    }
}

@available(iOS 17.0, *)
struct StartCurrentBlockLiveActivityIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Start Live Activity"
    static let description = IntentDescription("Start a Live Activity for the current block.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = try await SamoyedCurrentBlockLiveActivityController.start(
            using: .widgetLive,
            at: .now
        )
        WidgetCenter.shared.reloadTimelines(ofKind: SamoyedSharedConfig.widgetKind)
        return .result(dialog: IntentDialog(stringLiteral: outcome.userMessage))
    }
}
#endif
