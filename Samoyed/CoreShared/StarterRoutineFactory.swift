import Foundation

enum StarterRoutineFactory {
    static func makeRoutine(createdAt: Date = .now) throws -> SavedDayTemplate {
        let blocks = [
            BlockTemplate(
                layerIndex: 0,
                title: "Morning",
                taskBlueprints: [TaskBlueprint(title: "Choose today’s priorities")],
                timing: .absolute(startMinuteOfDay: 420, requestedEndMinuteOfDay: 540)
            ),
            BlockTemplate(
                layerIndex: 0,
                title: "Focus",
                taskBlueprints: [TaskBlueprint(title: "Work on the most important thing")],
                timing: .absolute(startMinuteOfDay: 540, requestedEndMinuteOfDay: 720)
            ),
            BlockTemplate(
                layerIndex: 0,
                title: "Lunch",
                taskBlueprints: [TaskBlueprint(title: "Take a real break")],
                timing: .absolute(startMinuteOfDay: 720, requestedEndMinuteOfDay: 780)
            ),
            BlockTemplate(
                layerIndex: 0,
                title: "Afternoon",
                taskBlueprints: [TaskBlueprint(title: "Review progress")],
                timing: .absolute(startMinuteOfDay: 780, requestedEndMinuteOfDay: 1080)
            ),
            BlockTemplate(
                layerIndex: 0,
                title: "Evening",
                taskBlueprints: [TaskBlueprint(title: "Prepare for tomorrow")],
                timing: .absolute(startMinuteOfDay: 1080, requestedEndMinuteOfDay: 1320)
            )
        ]
        let routine = SavedDayTemplate(
            title: "Workday",
            blocks: blocks,
            createdAt: createdAt,
            updatedAt: createdAt,
            provenance: RoutineVersionProvenance(source: .local, recordedAt: createdAt)
        )
        _ = try TemplateEngine.previewDayPlan(from: routine)
        return routine
    }

    static func makeDocument(
        today: LocalDay,
        startedAt: Date = .now
    ) throws -> SamoyedDocument {
        let routine = try makeRoutine(createdAt: startedAt)
        return try TemplateEngine.activate(
            document: SamoyedDocument(),
            template: routine,
            assignedWeekdays: [.monday, .tuesday, .wednesday, .thursday, .friday],
            today: today,
            activatedAt: startedAt
        )
    }
}
