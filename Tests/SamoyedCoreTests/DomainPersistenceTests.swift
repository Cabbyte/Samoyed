import Foundation
import XCTest
@testable import SamoyedCore

final class DomainPersistenceTests: XCTestCase {
    func testLegacyDocumentDefaultsNewCollectionsAndVersionIdentity() throws {
        let fixtureURL = try XCTUnwrap(
            Bundle.module.url(forResource: "document", withExtension: "json", subdirectory: "Fixtures")
        )
        let document = try JSONDecoder().decode(
            SamoyedDocument.self,
            from: Data(contentsOf: fixtureURL)
        )

        XCTAssertTrue(document.feedbackEvents.isEmpty)
        XCTAssertTrue(document.suggestions.isEmpty)
        XCTAssertTrue(document.routineRevisionSnapshots.isEmpty)
        XCTAssertEqual(document.plannerSettings.connectionState, .disconnected)
        let routine = try XCTUnwrap(document.savedTemplates.first)
        XCTAssertEqual(routine.logicalRoutineID, routine.id)
        XCTAssertEqual(routine.revision, 1)
        XCTAssertEqual(routine.versionID, routine.id)
        XCTAssertNil(routine.parentVersionID)
    }

    func testNewDocumentRoundTripPreservesDomainFields() throws {
        let routine = try StarterRoutineFactory.makeRoutine(createdAt: Date(timeIntervalSince1970: 10))
        let feedback = FeedbackEvent(
            target: .wholeDay,
            localDay: LocalDay(year: 2026, month: 8, day: 14),
            observedAt: Date(timeIntervalSince1970: 20),
            sentiment: .good,
            source: .today
        )
        let document = SamoyedDocument(
            savedTemplates: [routine],
            feedbackEvents: [feedback],
            plannerSettings: PlannerSettings(connectionState: .needsAttention)
        )

        let data = try JSONEncoder().encode(document)
        XCTAssertEqual(try JSONDecoder().decode(SamoyedDocument.self, from: data), document)
    }

    func testFeedbackIsAppendOnlyIdempotentTrimmedAndDoesNotChangeRuntime() throws {
        let repository = makeRepository()
        let baseline = try StarterRoutineFactory.makeDocument(
            today: LocalDay(year: 2026, month: 8, day: 14),
            startedAt: Date(timeIntervalSince1970: 10)
        )
        try repository.save(baseline)
        let service = FeedbackService(repository: repository)
        let id = UUID()
        let event = FeedbackEvent(
            id: id,
            target: .wholeDay,
            localDay: LocalDay(year: 2026, month: 8, day: 14),
            sentiment: .tired,
            note: "  Needed a break. \n",
            source: .now
        )

        XCTAssertEqual(try service.save(event).note, "Needed a break.")
        XCTAssertEqual(try service.save(event).id, id)

        let saved = try XCTUnwrap(repository.load())
        XCTAssertEqual(saved.feedbackEvents.count, 1)
        XCTAssertEqual(saved.feedbackEvents.first?.syncState, .localOnly)
        XCTAssertEqual(saved.savedTemplates, baseline.savedTemplates)
        XCTAssertEqual(saved.dayPlans, baseline.dayPlans)
        XCTAssertEqual(saved.weekdayRules, baseline.weekdayRules)
    }

    func testFeedbackValidationAndPendingOutboxPersistence() throws {
        let repository = makeRepository()
        let empty = FeedbackEvent(
            target: .wholeDay,
            localDay: LocalDay(year: 2026, month: 8, day: 14),
            note: " \n ",
            source: .today
        )
        XCTAssertThrowsError(try FeedbackService(repository: repository).save(empty)) { error in
            XCTAssertEqual(error as? FeedbackServiceError, .emptyFeedback)
        }
        XCTAssertNil(try repository.load())

        let pending = try FeedbackService(
            repository: repository,
            syncAvailability: .configuredOffline
        ).save(
            FeedbackEvent(
                target: .wholeDay,
                localDay: LocalDay(year: 2026, month: 8, day: 14),
                sentiment: .tooRushed,
                source: .today
            )
        )
        XCTAssertEqual(pending.syncState, .pending)
        XCTAssertEqual(try repository.load()?.feedbackEvents, [pending])
    }

    func testSuggestionTransportValidatesVersionSizeAndJSON() throws {
        let suggestion = makeDailySuggestion(target: LocalDay(year: 2026, month: 8, day: 15))
        let payload = try inlinePayload(suggestion)
        let decoder = SamoyedInlineSuggestionDecoder()
        XCTAssertEqual(try decoder.decode(version: 1, payload: payload), suggestion)

        XCTAssertThrowsError(try decoder.decode(version: 2, payload: payload)) { error in
            XCTAssertEqual(error as? SuggestionTransportError, .unsupportedVersion(2))
        }
        XCTAssertThrowsError(
            try SamoyedInlineSuggestionDecoder(maximumBytes: 8).decode(version: 1, payload: payload)
        ) { error in
            XCTAssertEqual(error as? SuggestionTransportError, .payloadTooLarge(maximumBytes: 8))
        }
        let corrupt = Data("not json".utf8).base64URLEncodedString()
        XCTAssertThrowsError(try decoder.decode(version: 1, payload: corrupt)) { error in
            XCTAssertEqual(error as? SuggestionTransportError, .invalidJSON)
        }
    }

    func testSuggestionImportDeduplicatesAndCorruptionDoesNotChangeDocument() throws {
        let repository = makeRepository()
        let service = SuggestionService(repository: repository)
        let suggestion = makeDailySuggestion(target: LocalDay(year: 2026, month: 8, day: 15))
        let payload = try inlinePayload(suggestion)

        XCTAssertEqual(try service.importSuggestion(version: 1, payload: payload), suggestion)
        XCTAssertEqual(try service.importSuggestion(version: 1, payload: payload), suggestion)
        XCTAssertEqual(try repository.load()?.suggestions.count, 1)
        let before = try repository.load()
        XCTAssertThrowsError(try service.importSuggestion(version: 1, payload: "%%%"))
        XCTAssertEqual(try repository.load(), before)
    }

    func testRejectSuggestionChangesOnlyLifecycleAndIsIdempotent() throws {
        let repository = makeRepository()
        let service = SuggestionService(repository: repository)
        let suggestion = makeDailySuggestion(target: LocalDay(year: 2026, month: 8, day: 15))
        _ = try service.importSuggestion(suggestion)
        let before = try XCTUnwrap(repository.load())

        let rejected = try service.reject(suggestion.id, at: Date(timeIntervalSince1970: 50))
        XCTAssertEqual(rejected.lifecycleState, .rejected)
        XCTAssertEqual(try service.reject(suggestion.id), rejected)
        let after = try XCTUnwrap(repository.load())
        XCTAssertEqual(after.dayPlans, before.dayPlans)
        XCTAssertEqual(after.savedTemplates, before.savedTemplates)
        XCTAssertEqual(after.weekdayRules, before.weekdayRules)
        XCTAssertThrowsError(try service.accept(suggestion.id, today: LocalDay(year: 2026, month: 8, day: 14)))
    }

    func testAcceptDailySuggestionOnlyChangesTargetDateAndNotUsualWeek() throws {
        let today = LocalDay(year: 2026, month: 8, day: 14)
        let target = today.adding(days: 1)
        let repository = makeRepository()
        let baseline = try StarterRoutineFactory.makeDocument(today: today, startedAt: Date(timeIntervalSince1970: 10))
        try repository.save(baseline)
        let service = SuggestionService(repository: repository)
        let suggestion = makeDailySuggestion(target: target)
        _ = try service.importSuggestion(suggestion)

        XCTAssertEqual(try service.accept(suggestion.id, today: today).lifecycleState, .accepted)
        let accepted = try XCTUnwrap(repository.load())
        XCTAssertEqual(accepted.dayPlan(for: today), baseline.dayPlan(for: today))
        XCTAssertEqual(accepted.dayPlan(for: target)?.blocks.first?.title, "Suggested Day")
        XCTAssertEqual(accepted.weekdayRules, baseline.weekdayRules)
        XCTAssertEqual(accepted.savedTemplates, baseline.savedTemplates)
        XCTAssertEqual(try service.accept(suggestion.id, today: today).lifecycleState, .accepted)
    }

    func testDailySuggestionRequiresConfirmationForExecutionState() throws {
        let target = LocalDay(year: 2026, month: 8, day: 15)
        let repository = makeRepository()
        var existing = makePlan(
            date: target,
            blocks: [baseBlock(title: "Existing", start: 480, requestedEnd: 720, tasks: [task("Done", completed: true)])]
        )
        existing = try DayPlanEngine.resolved(existing)
        try repository.save(SamoyedDocument(dayPlans: [existing]))
        let service = SuggestionService(repository: repository)
        let suggestion = makeDailySuggestion(target: target)
        _ = try service.importSuggestion(suggestion)

        XCTAssertThrowsError(try service.accept(suggestion.id, today: target.adding(days: -1))) { error in
            XCTAssertEqual(error as? SuggestionServiceError, .requiresExecutionStateConfirmation(target))
        }
        XCTAssertEqual(try repository.load()?.dayPlan(for: target), existing)
    }

    func testRoutineImprovementKeepsStableRoutineAndTodayWhileRecordingProvenance() throws {
        let today = LocalDay(year: 2026, month: 8, day: 14)
        let repository = makeRepository()
        let baseline = try StarterRoutineFactory.makeDocument(today: today, startedAt: Date(timeIntervalSince1970: 10))
        let routine = try XCTUnwrap(baseline.savedTemplates.first)
        try repository.save(baseline)
        let improvedBlock = templateBlock(
            title: "Improved Focus",
            timing: .absolute(startMinuteOfDay: 540, requestedEndMinuteOfDay: 720)
        )
        let feedbackID = UUID()
        let suggestion = Suggestion(
            kind: .routineImprovement,
            title: "Protect focus time",
            evidence: SuggestionEvidence(feedbackEventIDs: [feedbackID]),
            routineImprovementPayload: RoutineImprovementPayload(
                routineID: routine.id,
                proposedTitle: "Workday Improved",
                proposedBlocks: [improvedBlock]
            )
        )
        let service = SuggestionService(repository: repository)
        _ = try service.importSuggestion(suggestion)
        _ = try service.accept(suggestion.id, today: today, at: Date(timeIntervalSince1970: 100))

        let accepted = try XCTUnwrap(repository.load())
        let improved = try XCTUnwrap(accepted.savedTemplates.first)
        XCTAssertEqual(improved.id, routine.id)
        XCTAssertEqual(improved.logicalRoutineID, routine.logicalRoutineID)
        XCTAssertEqual(improved.revision, routine.revision + 1)
        XCTAssertEqual(improved.parentVersionID, routine.versionID)
        XCTAssertNotEqual(improved.versionID, routine.versionID)
        XCTAssertEqual(improved.provenance?.suggestionID, suggestion.id)
        XCTAssertEqual(improved.provenance?.feedbackEventIDs, [feedbackID])
        XCTAssertEqual(accepted.routineRevisionSnapshots.first?.versionID, routine.versionID)
        XCTAssertEqual(accepted.dayPlan(for: today), baseline.dayPlan(for: today))
        XCTAssertEqual(accepted.weekdayRules, baseline.weekdayRules)
    }

    func testStarterRoutineAssignsWeekdaysAndMaterializesToday() throws {
        let today = LocalDay(year: 2026, month: 8, day: 14)
        let document = try StarterRoutineFactory.makeDocument(today: today)
        XCTAssertEqual(document.savedTemplates.map(\.title), ["Workday"])
        XCTAssertEqual(
            Set(document.weekdayRules.map(\.weekday)),
            [.monday, .tuesday, .wednesday, .thursday, .friday]
        )
        XCTAssertFalse(try XCTUnwrap(document.dayPlan(for: today)).blocks.isEmpty)
    }

    private func makeRepository() -> SamoyedDocumentRepository {
        let fileURL = FileManager.default.temporaryDirectory
            .appending(path: "SamoyedDomainTests-\(UUID().uuidString)", directoryHint: .isDirectory)
            .appending(path: "document.json")
        return SamoyedDocumentRepository(fileURL: fileURL)
    }

    private func makeDailySuggestion(target: LocalDay) -> Suggestion {
        let plan = DayPlan(
            date: target,
            blocks: [baseBlock(title: "Suggested Day", start: 480, requestedEnd: 720)]
        )
        return Suggestion(
            kind: .dailyPlan,
            title: "A calmer tomorrow",
            dailyPlanPayload: DailyPlanSuggestionPayload(targetDate: target, proposedDayPlan: plan)
        )
    }

    private func inlinePayload(_ suggestion: Suggestion) throws -> String {
        try JSONEncoder().encode(suggestion).base64URLEncodedString()
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
