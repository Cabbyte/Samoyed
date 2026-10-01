#if DEBUG
import Foundation

/// Stable, local-only documents used by previews and UI automation.
///
/// Keep these fixtures independent from `SampleDataFactory`: UI tests need fixed
/// identifiers and dates so they can exercise semantic accessibility contracts.
enum SamoyedQAFixtureFactory {
    static let workdayRoutineID = uuid("10000000-0000-0000-0000-000000000001")
    static let recoveryRoutineID = uuid("10000000-0000-0000-0000-000000000002")
    static let dailySuggestionID = uuid("20000000-0000-0000-0000-000000000001")
    static let improvementSuggestionID = uuid("20000000-0000-0000-0000-000000000002")

    private static let generatedAt = Date(timeIntervalSince1970: 1_710_000_000)
    private static let workdayPlanID = uuid("30000000-0000-0000-0000-000000000001")
    private static let morningBlockID = uuid("40000000-0000-0000-0000-000000000001")
    private static let afternoonBlockID = uuid("40000000-0000-0000-0000-000000000002")
    private static let projectBlockID = uuid("40000000-0000-0000-0000-000000000003")

    static func document(named name: String, today: LocalDay = .today()) -> SamoyedDocument? {
        switch name {
        case "first-run", "empty":
            return SamoyedDocument()

        case "frozen-runtime", "active", "complex", "feedback-validation":
            return frozenRuntimeDocument(today: today)

        case "feedback-saved":
            return frozenRuntimeDocument(
                today: today,
                feedbackEvents: [feedbackEvent(on: today, syncState: .localOnly)]
            )

        case "feedback-offline":
            return frozenRuntimeDocument(
                today: today,
                feedbackEvents: [feedbackEvent(on: today, syncState: .pending)]
            )

        case "suggestions-empty":
            return frozenRuntimeDocument(today: today)

        case "suggestions-pending":
            return frozenRuntimeDocument(today: today, suggestions: pendingSuggestions(today: today))

        case "suggestions-handled":
            return frozenRuntimeDocument(today: today, suggestions: handledSuggestions(today: today))

        case "planner-disconnected":
            return frozenRuntimeDocument(
                today: today,
                plannerSettings: PlannerSettings(connectionState: .disconnected)
            )

        case "planner-connected":
            return frozenRuntimeDocument(
                today: today,
                plannerSettings: PlannerSettings(
                    connectionState: .connected,
                    planningTime: DateComponents(hour: 20, minute: 30),
                    externalURL: URL(string: "https://chatgpt.com/")
                )
            )

        case "planner-unavailable":
            return frozenRuntimeDocument(
                today: today,
                plannerSettings: PlannerSettings(connectionState: .unavailable)
            )

        case "planner-needs-attention":
            return frozenRuntimeDocument(
                today: today,
                plannerSettings: PlannerSettings(connectionState: .needsAttention)
            )

        case "no-routine":
            return noRoutineDocument(today: today)

        case "open-time":
            return openTimeDocument(today: today)

        case "all-done":
            return allDoneDocument(today: today)

        case "single-layer-days":
            return singleLayerDaysDocument(today: today)

        case "elastic-timeline":
            return elasticTimelineDocument(today: today)

        case "coincident-starts":
            var document = frozenRuntimeDocument(today: today)
            for planIndex in document.dayPlans.indices {
                for blockIndex in document.dayPlans[planIndex].blocks.indices
                where document.dayPlans[planIndex].blocks[blockIndex].layerIndex == 1 {
                    document.dayPlans[planIndex].blocks[blockIndex].timing = .relative(
                        startOffsetMinutes: 0, requestedDurationMinutes: 150
                    )
                }
                document.dayPlans[planIndex] = resolved(document.dayPlans[planIndex])
            }
            for routineIndex in document.savedTemplates.indices {
                for blockIndex in document.savedTemplates[routineIndex].blocks.indices
                where document.savedTemplates[routineIndex].blocks[blockIndex].layerIndex == 1 {
                    document.savedTemplates[routineIndex].blocks[blockIndex].timing = .relative(
                        startOffsetMinutes: 0, requestedDurationMinutes: 150
                    )
                }
            }
            return document

        case "long-title":
            var document = frozenRuntimeDocument(today: today)
            let title = "Project work and thoughtful planning"
            for planIndex in document.dayPlans.indices {
                for blockIndex in document.dayPlans[planIndex].blocks.indices
                where document.dayPlans[planIndex].blocks[blockIndex].layerIndex == 1 {
                    document.dayPlans[planIndex].blocks[blockIndex].title = title
                }
            }
            for routineIndex in document.savedTemplates.indices {
                for blockIndex in document.savedTemplates[routineIndex].blocks.indices
                where document.savedTemplates[routineIndex].blocks[blockIndex].layerIndex == 1 {
                    document.savedTemplates[routineIndex].blocks[blockIndex].title = title
                }
            }
            return document

        default:
            return nil
        }
    }

    static func frozenRuntimeDocument(
        today: LocalDay = .today(),
        feedbackEvents: [FeedbackEvent] = [],
        suggestions: [Suggestion] = [],
        plannerSettings: PlannerSettings = PlannerSettings()
    ) -> SamoyedDocument {
        let workday = workdayRoutine()
        let recovery = recoveryRoutine()
        let plan = resolved(
            DayPlan(
                id: workdayPlanID,
                date: today,
                sourceSavedTemplateID: workday.id,
                lastGeneratedAt: generatedAt,
                blocks: runtimeBlocks(dayPlanID: workdayPlanID)
            )
        )

        return SamoyedDocument(
            dayPlans: [plan],
            savedTemplates: [workday, recovery],
            weekdayRules: Weekday.allCases.map {
                WeekdayTemplateRule(weekday: $0, savedTemplateID: workday.id)
            },
            daySelections: [
                DayTemplateSelection(
                    date: today,
                    selectedTemplateID: workday.id,
                    source: .pickedTemplate,
                    selectedAt: generatedAt
                )
            ],
            feedbackEvents: feedbackEvents,
            suggestions: suggestions,
            plannerSettings: plannerSettings
        )
    }

    private static func noRoutineDocument(today: LocalDay) -> SamoyedDocument {
        let workday = workdayRoutine()
        return SamoyedDocument(
            dayPlans: [
                DayPlan(
                    id: uuid("30000000-0000-0000-0000-000000000099"),
                    date: today,
                    lastGeneratedAt: generatedAt
                )
            ],
            savedTemplates: [workday, recoveryRoutine()],
            weekdayRules: Weekday.allCases.map {
                WeekdayTemplateRule(weekday: $0, savedTemplateID: workday.id)
            },
            daySelections: [
                DayTemplateSelection(
                    date: today,
                    selectedTemplateID: nil,
                    source: .noTemplate,
                    selectedAt: generatedAt
                )
            ]
        )
    }

    private static func openTimeDocument(today: LocalDay) -> SamoyedDocument {
        SamoyedDocument(
            dayPlans: [
                resolved(
                    DayPlan(
                        date: today,
                        lastGeneratedAt: generatedAt,
                        blocks: [
                            TimeBlock(
                                layerIndex: 0,
                                title: "Earlier",
                                timing: .absolute(
                                    startMinuteOfDay: 420,
                                    requestedEndMinuteOfDay: 720
                                )
                            ),
                            TimeBlock(
                                layerIndex: 0,
                                title: "Later",
                                timing: .absolute(
                                    startMinuteOfDay: 900,
                                    requestedEndMinuteOfDay: 1080
                                )
                            )
                        ]
                    )
                )
            ]
        )
    }

    private static func allDoneDocument(today: LocalDay) -> SamoyedDocument {
        SamoyedDocument(
            dayPlans: [
                resolved(
                    DayPlan(
                        date: today,
                        lastGeneratedAt: generatedAt,
                        blocks: [
                            TimeBlock(
                                layerIndex: 0,
                                title: "Finished",
                                tasks: [
                                    TaskItem(
                                        title: "Done",
                                        isCompleted: true,
                                        completedAt: generatedAt
                                    )
                                ],
                                timing: .absolute(
                                    startMinuteOfDay: 780,
                                    requestedEndMinuteOfDay: 1080
                                )
                            )
                        ]
                    )
                )
            ]
        )
    }

    private static func workdayRoutine() -> SavedDayTemplate {
        let morning = uuid("50000000-0000-0000-0000-000000000001")
        let afternoon = uuid("50000000-0000-0000-0000-000000000002")
        return SavedDayTemplate(
            id: workdayRoutineID,
            title: "Workday",
            blocks: [
                BlockTemplate(
                    id: morning,
                    layerIndex: 0,
                    title: "Morning",
                    note: "Start gently and protect the first hour.",
                    taskBlueprints: [TaskBlueprint(title: "Plan the day")],
                    timing: .absolute(startMinuteOfDay: 420, requestedEndMinuteOfDay: 720)
                ),
                BlockTemplate(
                    id: afternoon,
                    layerIndex: 0,
                    title: "Afternoon",
                    note: "Keep the day moving without changing the approved routine.",
                    reminders: [ReminderRule(triggerMode: .beforeStart, offsetMinutes: 15)],
                    taskBlueprints: [
                        TaskBlueprint(title: "Review progress"),
                        TaskBlueprint(title: "Wrap up", order: 1)
                    ],
                    timing: .absolute(startMinuteOfDay: 780, requestedEndMinuteOfDay: 1080)
                ),
                BlockTemplate(
                    id: uuid("50000000-0000-0000-0000-000000000003"),
                    parentTemplateBlockID: afternoon,
                    layerIndex: 1,
                    title: "Project Work",
                    note: "Ship one calm milestone.",
                    taskBlueprints: [TaskBlueprint(title: "Ship milestone")],
                    timing: .relative(startOffsetMinutes: 15, requestedDurationMinutes: 150)
                ),
                BlockTemplate(
                    id: uuid("50000000-0000-0000-0000-000000000004"),
                    layerIndex: 0,
                    title: "Evening",
                    taskBlueprints: [TaskBlueprint(title: "Prepare tomorrow")],
                    timing: .absolute(startMinuteOfDay: 1080, requestedEndMinuteOfDay: 1320)
                )
            ],
            createdAt: generatedAt,
            updatedAt: generatedAt,
            provenance: RoutineVersionProvenance(source: .local, recordedAt: generatedAt)
        )
    }

    private static func recoveryRoutine() -> SavedDayTemplate {
        SavedDayTemplate(
            id: recoveryRoutineID,
            title: "Recovery Day",
            blocks: [
                BlockTemplate(
                    id: uuid("50000000-0000-0000-0000-000000000011"),
                    layerIndex: 0,
                    title: "Slow Morning",
                    taskBlueprints: [TaskBlueprint(title: "Take a short walk")],
                    timing: .absolute(startMinuteOfDay: 540, requestedEndMinuteOfDay: 720)
                ),
                BlockTemplate(
                    id: uuid("50000000-0000-0000-0000-000000000012"),
                    layerIndex: 0,
                    title: "Light Afternoon",
                    taskBlueprints: [TaskBlueprint(title: "Close one loop")],
                    timing: .absolute(startMinuteOfDay: 780, requestedEndMinuteOfDay: 960)
                )
            ],
            createdAt: generatedAt,
            updatedAt: generatedAt,
            provenance: RoutineVersionProvenance(source: .local, recordedAt: generatedAt)
        )
    }

    private static func runtimeBlocks(dayPlanID: UUID) -> [TimeBlock] {
        [
            TimeBlock(
                id: morningBlockID,
                dayPlanID: dayPlanID,
                layerIndex: 0,
                title: "Morning",
                note: "Start gently and protect the first hour.",
                tasks: [
                    TaskItem(
                        id: uuid("60000000-0000-0000-0000-000000000001"),
                        title: "Plan the day"
                    )
                ],
                timing: .absolute(startMinuteOfDay: 420, requestedEndMinuteOfDay: 720)
            ),
            TimeBlock(
                id: afternoonBlockID,
                dayPlanID: dayPlanID,
                layerIndex: 0,
                title: "Afternoon",
                note: "Keep the day moving without changing the approved routine.",
                reminders: [
                    ReminderRule(
                        id: uuid("70000000-0000-0000-0000-000000000001"),
                        triggerMode: .beforeStart,
                        offsetMinutes: 15
                    )
                ],
                tasks: [
                    TaskItem(
                        id: uuid("60000000-0000-0000-0000-000000000002"),
                        title: "Review progress"
                    ),
                    TaskItem(
                        id: uuid("60000000-0000-0000-0000-000000000003"),
                        title: "Wrap up",
                        order: 1
                    )
                ],
                timing: .absolute(startMinuteOfDay: 780, requestedEndMinuteOfDay: 1080)
            ),
            TimeBlock(
                id: projectBlockID,
                dayPlanID: dayPlanID,
                parentBlockID: afternoonBlockID,
                layerIndex: 1,
                title: "Project Work",
                note: "Ship one calm milestone.",
                tasks: [
                    TaskItem(
                        id: uuid("60000000-0000-0000-0000-000000000004"),
                        title: "Ship milestone"
                    )
                ],
                timing: .relative(startOffsetMinutes: 15, requestedDurationMinutes: 150)
            ),
            TimeBlock(
                id: uuid("40000000-0000-0000-0000-000000000004"),
                dayPlanID: dayPlanID,
                layerIndex: 0,
                title: "Evening",
                tasks: [
                    TaskItem(
                        id: uuid("60000000-0000-0000-0000-000000000005"),
                        title: "Prepare tomorrow"
                    )
                ],
                timing: .absolute(startMinuteOfDay: 1080, requestedEndMinuteOfDay: 1320)
            )
        ]
    }

    private static func feedbackEvent(
        on day: LocalDay,
        syncState: FeedbackSyncState
    ) -> FeedbackEvent {
        FeedbackEvent(
            id: uuid("80000000-0000-0000-0000-000000000001"),
            target: .block(blockID: projectBlockID),
            localDay: day,
            observedAt: generatedAt,
            sentiment: .good,
            note: "The pace felt sustainable.",
            source: .now,
            syncState: syncState
        )
    }

    private static func pendingSuggestions(today: LocalDay) -> [Suggestion] {
        [dailySuggestion(today: today), improvementSuggestion()]
    }

    private static func handledSuggestions(today: LocalDay) -> [Suggestion] {
        var daily = dailySuggestion(today: today)
        daily.lifecycleState = .accepted
        var improvement = improvementSuggestion()
        improvement.lifecycleState = .rejected
        return [daily, improvement]
    }

    private static func dailySuggestion(today: LocalDay) -> Suggestion {
        let targetDate = today.adding(days: 1)
        let proposedPlan = resolved(
            DayPlan(
                id: uuid("30000000-0000-0000-0000-000000000010"),
                date: targetDate,
                sourceSavedTemplateID: recoveryRoutineID,
                lastGeneratedAt: generatedAt,
                blocks: [
                    TimeBlock(
                        id: uuid("40000000-0000-0000-0000-000000000010"),
                        layerIndex: 0,
                        title: "Slow Morning",
                        tasks: [TaskItem(title: "Take a short walk")],
                        timing: .absolute(startMinuteOfDay: 540, requestedEndMinuteOfDay: 720)
                    ),
                    TimeBlock(
                        id: uuid("40000000-0000-0000-0000-000000000011"),
                        layerIndex: 0,
                        title: "Light Afternoon",
                        tasks: [TaskItem(title: "Close one loop")],
                        timing: .absolute(startMinuteOfDay: 780, requestedEndMinuteOfDay: 960)
                    )
                ]
            )
        )
        return Suggestion(
            id: dailySuggestionID,
            kind: .dailyPlan,
            title: "A calmer plan for tomorrow",
            summary: "Use the Recovery Day routine after today’s tired feedback.",
            changes: [
                SuggestionChange(
                    id: uuid("21000000-0000-0000-0000-000000000001"),
                    title: "Start later",
                    detail: "Move the first structured block to 09:00."
                )
            ],
            evidence: SuggestionEvidence(summary: "Based on one saved feedback event."),
            dailyPlanPayload: DailyPlanSuggestionPayload(
                targetDate: targetDate,
                proposedDayPlan: proposedPlan
            ),
            createdAt: generatedAt
        )
    }

    private static func improvementSuggestion() -> Suggestion {
        Suggestion(
            id: improvementSuggestionID,
            kind: .routineImprovement,
            title: "Protect a shorter focus block",
            summary: "Create a new routine version with a shorter focus window.",
            changes: [
                SuggestionChange(
                    id: uuid("21000000-0000-0000-0000-000000000002"),
                    title: "Shorten Project Work",
                    detail: "Keep the current routine unchanged until approval."
                )
            ],
            evidence: SuggestionEvidence(summary: "Repeated pace feedback suggests a smaller block."),
            routineImprovementPayload: RoutineImprovementPayload(
                routineID: workdayRoutineID,
                proposedTitle: "Workday · Calmer Focus",
                proposedBlocks: workdayRoutine().blocks
            ),
            createdAt: generatedAt.addingTimeInterval(-60)
        )
    }

    private static func singleLayerDaysDocument(today: LocalDay) -> SamoyedDocument {
        let tomorrow = today.adding(days: 1)
        let plans = [today, tomorrow].map { day in
            resolved(
                DayPlan(
                    date: day,
                    sourceSavedTemplateID: workdayRoutineID,
                    lastGeneratedAt: generatedAt,
                    blocks: runtimeBlocks(dayPlanID: UUID()).filter { $0.layerIndex == 0 }
                )
            )
        }
        return SamoyedDocument(
            dayPlans: plans,
            savedTemplates: [workdayRoutine()],
            weekdayRules: Weekday.allCases.map {
                WeekdayTemplateRule(weekday: $0, savedTemplateID: workdayRoutineID)
            }
        )
    }

    private static func elasticTimelineDocument(today: LocalDay) -> SamoyedDocument {
        SamoyedDocument(
            dayPlans: [
                resolved(
                    DayPlan(
                        date: today,
                        sourceSavedTemplateID: workdayRoutineID,
                        lastGeneratedAt: generatedAt,
                        blocks: runtimeBlocks(dayPlanID: UUID())
                    )
                )
            ],
            savedTemplates: [workdayRoutine()],
            weekdayRules: Weekday.allCases.map {
                WeekdayTemplateRule(weekday: $0, savedTemplateID: workdayRoutineID)
            }
        )
    }

    private static func resolved(_ plan: DayPlan) -> DayPlan {
        do {
            return try DayPlanEngine.resolved(plan)
        } catch {
            preconditionFailure("Invalid QA fixture: \(error)")
        }
    }

    private static func uuid(_ value: String) -> UUID {
        guard let uuid = UUID(uuidString: value) else {
            preconditionFailure("Invalid QA fixture UUID: \(value)")
        }
        return uuid
    }
}
#endif
