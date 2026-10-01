import XCTest
@testable import SamoyedCore

final class P0FlowTests: XCTestCase {
    func testSavedTemplateRoundTripsSuggestedSourceAndAllowsDirectCreation() throws {
        let suggestedSource = UUID()
        let sourced = SavedDayTemplate(title: "Suggested", sourceSuggestedTemplateID: suggestedSource, blocks: [])
        let decoded = try JSONDecoder().decode(
            SavedDayTemplate.self,
            from: JSONEncoder().encode(sourced)
        )
        XCTAssertEqual(decoded.sourceSuggestedTemplateID, suggestedSource)

        let direct = try TemplateEngine.makeSimpleSavedTemplate(
            title: "Workday",
            blocks: [templateBlock(title: "Morning", timing: .absolute(startMinuteOfDay: 480, requestedEndMinuteOfDay: 720))]
        )
        XCTAssertNil(direct.sourceSuggestedTemplateID)
    }

    func testActivationCreatesTemplateRulesSelectionAndTodayPlanAtomically() throws {
        let today = LocalDay(year: 2026, month: 8, day: 8)
        let template = try TemplateEngine.makeSimpleSavedTemplate(
            title: " Workday ",
            blocks: [
                templateBlock(
                    title: "Morning",
                    tasks: [TaskBlueprint(title: "Plan priorities")],
                    timing: .absolute(startMinuteOfDay: 480, requestedEndMinuteOfDay: 720)
                )
            ]
        )

        let activated = try TemplateEngine.activate(
            document: SamoyedDocument(),
            template: template,
            assignedWeekdays: [.monday, .tuesday, .wednesday, .thursday, .friday],
            today: today,
            activatedAt: Date(timeIntervalSince1970: 10)
        )

        XCTAssertEqual(activated.savedTemplates.map(\.title), ["Workday"])
        XCTAssertEqual(Set(activated.weekdayRules.map(\.weekday)), [.monday, .tuesday, .wednesday, .thursday, .friday])
        XCTAssertEqual(activated.daySelection(for: today)?.selectedTemplateID, template.id)
        XCTAssertEqual(activated.dayPlan(for: today)?.sourceSavedTemplateID, template.id)
        XCTAssertEqual(activated.dayPlan(for: today)?.blocks.first?.tasks.first?.title, "Plan priorities")
    }

    func testActivationValidationDoesNotMutateInput() throws {
        let original = SamoyedDocument()
        let template = try TemplateEngine.makeSimpleSavedTemplate(
            title: "Workday",
            blocks: [templateBlock(title: "Morning", timing: .absolute(startMinuteOfDay: 480, requestedEndMinuteOfDay: 720))]
        )

        XCTAssertThrowsError(
            try TemplateEngine.activate(
                document: original,
                template: template,
                assignedWeekdays: [],
                today: LocalDay(year: 2026, month: 8, day: 8)
            )
        )
        XCTAssertTrue(original.isEmptyForActivation)
    }

    func testDefaultsNeverRequireDailyConfirmation() throws {
        let today = LocalDay(year: 2026, month: 8, day: 7)
        XCTAssertFalse(
            try TemplateEngine.requiresExplicitTemplateSelection(
                for: today,
                today: today,
                existingDayPlans: [],
                daySelections: []
            )
        )
    }

    func testUpcomingActiveBlockSkipsOpenTimeAndReturnsParentAfterOverlay() throws {
        let baseID = UUID()
        let overlayID = UUID()
        let plan = makePlan(blocks: [
            baseBlock(id: baseID, title: "Morning", start: 480, requestedEnd: 720),
            overlayRelative(
                id: overlayID,
                parentID: baseID,
                layerIndex: 1,
                title: "Focus",
                offset: 30,
                duration: 60
            ),
            baseBlock(title: "Afternoon", start: 780, requestedEnd: 1080)
        ])

        let beforeFirst = try XCTUnwrap(DayPlanEngine.upcomingActiveBlock(in: plan, after: 420))
        XCTAssertEqual(beforeFirst.block.id, baseID)
        XCTAssertEqual(beforeFirst.transitionMinuteOfDay, 480)

        let afterOverlay = try XCTUnwrap(DayPlanEngine.upcomingActiveBlock(in: plan, after: 550))
        XCTAssertEqual(afterOverlay.block.id, baseID)
        XCTAssertEqual(afterOverlay.transitionMinuteOfDay, 570)

        let throughGap = try XCTUnwrap(DayPlanEngine.upcomingActiveBlock(in: plan, after: 730))
        XCTAssertEqual(throughGap.block.title, "Afternoon")
        XCTAssertEqual(throughGap.transitionMinuteOfDay, 780)
    }

    func testValidationEventEncodingHasNoUserContentFields() throws {
        let event = ValidationEvent(
            participantID: UUID(),
            sessionID: UUID(),
            occurredAt: Date(timeIntervalSince1970: 100),
            name: .todayCorrectionCompleted,
            outcome: "saved",
            variant: "today-only",
            durationMilliseconds: 900
        )
        let json = String(decoding: try JSONEncoder().encode(event), as: UTF8.self)

        XCTAssertFalse(json.contains("title"))
        XCTAssertFalse(json.contains("note"))
        XCTAssertFalse(json.contains("task"))
        XCTAssertFalse(json.contains("templateID"))
    }
}
