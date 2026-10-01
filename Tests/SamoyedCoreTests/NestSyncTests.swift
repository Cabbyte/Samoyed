import Foundation
import XCTest
import GRDB
@testable import SamoyedCore

final class NestSyncTests: XCTestCase {
    private func database() throws -> NestLocalDatabase {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("sync.sqlite")
        return try NestLocalDatabase(url: url, partition: "test/alice")
    }
    private func entity(_ note: TimelineNote, revision: Int, deleted: Bool = false) throws -> NestRemoteEntity {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        return .init(kind: "note", id: note.id.uuidString.lowercased(), revision: revision, deleted: deleted, body: try JSONDecoder().decode(NestJSON.self, from: encoder.encode(note)))
    }
    func testPullPreservesOptimisticEditAndAdvancesCursorDurably() throws {
        let db = try database(); var note = TimelineNote(text: "Remote")
        try db.apply(.init(cursor: "first", hasMore: false, changes: [try entity(note, revision: 1)]))
        _ = try db.mutate { $0.timelineNotes[0].text = "Local pending" }
        note.text = "Other device"
        try db.apply(.init(cursor: "second", hasMore: false, changes: [try entity(note, revision: 2)]))
        XCTAssertEqual(try db.load()?.timelineNotes[0].text, "Local pending")
        XCTAssertEqual(try db.cursor(), "second"); XCTAssertEqual(try db.pendingOperations().count, 1)
    }
    func testAcknowledgementDoesNotOverwriteLaterQueuedEdit() throws {
        let db = try database(); let note = TimelineNote(text: "First")
        _ = try db.mutate { $0.timelineNotes.append(note) }
        _ = try db.mutate { $0.timelineNotes[0].text = "Second" }
        let pending = try db.pendingOperations(); let remote = try entity(note, revision: 1)
        try db.acknowledge([.init(operationID: pending[0].operationID, status: "accepted", revision: 1, body: remote.body, deleted: false)])
        XCTAssertEqual(try db.load()?.timelineNotes[0].text, "Second")
        XCTAssertEqual(try db.pendingOperations().map(\.operationID), [pending[1].operationID])
    }
    func testConflictBlocksDependentOperationsWithoutDiscardingLocalContent() throws {
        let db = try database(); let note = TimelineNote(text: "Local")
        _ = try db.mutate { $0.timelineNotes.append(note) }
        _ = try db.mutate { $0.timelineNotes[0].text = "Still local" }
        let first = try XCTUnwrap(db.pendingOperations().first)
        var other = note; other.text = "Remote"
        try db.acknowledge([.init(operationID: first.operationID, status: "rejected", error: "revision_conflict", details: .init(remote: try entity(other, revision: 1)))])
        XCTAssertTrue(try db.pendingOperations().isEmpty)
        XCTAssertEqual(try db.load()?.timelineNotes[0].text, "Still local")
    }
    func testMalformedPageRollsBackCursorAndEntities() throws {
        let db = try database(), note = TimelineNote(text: "Initial")
        try db.apply(.init(cursor: "first", hasMore: false, changes: [try entity(note, revision: 1)]))
        let malformed = NestRemoteEntity(kind: "note", id: UUID().uuidString, revision: 1, deleted: false, body: .null)
        XCTAssertThrowsError(try db.apply(.init(cursor: "bad", hasMore: false, changes: [malformed])))
        XCTAssertEqual(try db.cursor(), "first"); XCTAssertEqual(try db.load()?.timelineNotes.count, 1)
    }
}

extension NestSyncTests {
    func testPlanRefreshPreservesPendingCompletionAndUndo() throws {
        let db = try database()
        var plan = DayPlan(date: .init(year: 2030, month: 10, day: 1))
        plan.revision = 1; plan.sourceRevision = 1; plan.timeZoneID = "Asia/Shanghai"
        plan.blocks = [.init(dayPlanID: plan.id, layerIndex: 0, title: "Morning", tasks: [.init(title: "Water")], timing: .absolute(startMinuteOfDay: 540, requestedEndMinuteOfDay: 600))]
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        func remote(_ plan: DayPlan) throws -> NestRemoteEntity {
            .init(kind: "plan", id: plan.id.uuidString.lowercased(), revision: plan.revision!, deleted: false, body: try JSONDecoder().decode(NestJSON.self, from: encoder.encode(plan)))
        }
        try db.apply(.init(cursor: "a", hasMore: false, changes: [try remote(plan)]))
        _ = try db.mutate { $0.dayPlans[0].blocks[0].tasks[0].isCompleted = true; $0.dayPlans[0].blocks[0].tasks[0].completedAt = .now }
        plan.revision = 2
        try db.apply(.init(cursor: "b", hasMore: false, changes: [try remote(plan)]))
        XCTAssertEqual(try db.load()?.dayPlans[0].blocks[0].tasks[0].isCompleted, true)
        _ = try db.mutate { $0.dayPlans[0].blocks[0].tasks[0].isCompleted = false; $0.dayPlans[0].blocks[0].tasks[0].completedAt = nil }
        plan.blocks[0].tasks[0].isCompleted = true; plan.revision = 3
        try db.apply(.init(cursor: "c", hasMore: false, changes: [try remote(plan)]))
        XCTAssertEqual(try db.load()?.dayPlans[0].blocks[0].tasks[0].isCompleted, false)
        XCTAssertEqual(try db.pendingOperations().count, 2)
    }

    func testInitialImportIsRetryableAndArchivesUnlinkedHistory() throws {
        let db = try database()
        var document = SamoyedDocument()
        document.timelineNotes = [.init(text: "Backdated")]
        document.dayPlans = [.init(date: .init(year: 2025, month: 1, day: 1))]
        try db.importLocal(document); try db.importLocal(document)
        XCTAssertEqual(try db.load()?.dayPlans[0].source, "legacy")
        XCTAssertEqual(try db.load()?.timelineNotes.count, 1)
        XCTAssertEqual(try db.pendingOperations().map(\.kind), ["legacyPlan", "note"])
    }
    func testConflictRecoveryKeepsBothVersionsAndQueuesLatestLocalEdit() throws {
        let db = try database(); var note = TimelineNote(text: "Original")
        try db.apply(.init(cursor: "base", hasMore: false, changes: [try entity(note, revision: 1)]))
        _ = try db.mutate { $0.timelineNotes[0].text = "Local edit" }
        let operation = try XCTUnwrap(db.pendingOperations().first)
        note.text = "Remote edit"
        try db.acknowledge([.init(operationID: operation.operationID, status: "rejected", error: "revision_conflict", details: .init(remote: try entity(note, revision: 2)))])
        _ = try db.mutate { $0.timelineNotes[0].text = "Later local edit" }
        XCTAssertTrue(try db.pendingOperations().isEmpty)
        let conflict = try XCTUnwrap(db.noteConflicts().first)
        XCTAssertEqual(conflict.local.text, "Later local edit"); XCTAssertEqual(conflict.remote?.text, "Remote edit")
        try db.resolveNoteConflict(operationID: conflict.id, choice: .keepLocal)
        XCTAssertTrue(try db.noteConflicts().isEmpty)
        XCTAssertEqual(try db.pendingOperations().map(\.expectedRevision), [2])
        XCTAssertEqual(try db.load()?.timelineNotes.first?.text, "Later local edit")
    }

    func testKeepingLocalAfterRemoteDeletionCreatesNewID() throws {
        let db = try database(); let note = TimelineNote(text: "Original")
        try db.apply(.init(cursor: "base", hasMore: false, changes: [try entity(note, revision: 1)]))
        _ = try db.mutate { $0.timelineNotes[0].text = "Offline change" }
        let operation = try XCTUnwrap(db.pendingOperations().first)
        try db.acknowledge([.init(operationID: operation.operationID, status: "rejected", error: "revision_conflict", details: .init(remote: try entity(note, revision: 2, deleted: true)))])
        try db.resolveNoteConflict(operationID: operation.operationID, choice: .keepLocal)
        let pending = try XCTUnwrap(db.pendingOperations().first)
        XCTAssertNotEqual(pending.entityID, note.id.uuidString.lowercased())
        XCTAssertEqual(pending.expectedRevision, 0)
        XCTAssertNotNil(try db.load()?.timelineNotes.first(where: { $0.id == note.id })?.deletedAt)
    }
}

extension NestSyncTests {
    func testRoutineConflictChoicesArchiveAndRebaseOnlyAfterChoice() throws {
        for keepLocal in [false, true] {
            let db = try database()
            var routine = SavedDayTemplate(title: "Original", blocks: [])
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            func remote(_ revision: Int) throws -> NestRemoteEntity {
                .init(kind: "routine", id: routine.id.uuidString.lowercased(), revision: revision, deleted: false, body: try JSONDecoder().decode(NestJSON.self, from: encoder.encode(routine)))
            }
            try db.apply(.init(cursor: "first", hasMore: false, changes: [try remote(1)]))
            _ = try db.mutate { $0.savedTemplates[0].title = "My edit" }
            let operation = try XCTUnwrap(db.pendingOperations().first)
            routine.title = "Other device"
            try db.acknowledge([.init(operationID: operation.operationID, status: "rejected", error: "revision_conflict", details: .init(remote: try remote(2)))])
            XCTAssertEqual(try db.blockedOperationCount(), 1)
            XCTAssertEqual(try db.domainConflicts().count, 1)
            try db.resolveDomainConflict(operationID: operation.operationID, keepLocal: keepLocal)
            XCTAssertEqual(try db.load()?.savedTemplates[0].title, keepLocal ? "My edit" : "Other device")
            XCTAssertEqual(try db.blockedOperationCount(), 0)
            XCTAssertEqual(try db.pendingOperations().count, keepLocal ? 1 : 0)
            if keepLocal {
                let rebased = try XCTUnwrap(db.pendingOperations().first)
                XCTAssertEqual(rebased.expectedRevision, 2)
                XCTAssertNotEqual(rebased.operationID, operation.operationID)
            }
        }
    }
    func testGenericConflictCannotResurrectDeletedRoutine() throws {
        let db = try database(), routine = SavedDayTemplate(title: "Local routine", blocks: [])
        _ = try db.mutate { $0.savedTemplates.append(routine) }
        let op = try XCTUnwrap(db.pendingOperations().first)
        let remote = NestRemoteEntity(kind: "routine", id: op.entityID, revision: 2, deleted: true, body: try JSONDecoder().decode(NestJSON.self, from: op.payload))
        try db.acknowledge([.init(operationID: op.operationID, status: "rejected", error: "revision_conflict", details: .init(remote: remote))])
        XCTAssertFalse(try XCTUnwrap(db.domainConflicts().first).canKeepLocal)
        XCTAssertThrowsError(try db.resolveDomainConflict(operationID: op.operationID, keepLocal: true))
        try db.resolveDomainConflict(operationID: op.operationID, keepLocal: false)
        XCTAssertTrue(try XCTUnwrap(db.load()).savedTemplates.isEmpty)
        XCTAssertTrue(try db.pendingOperations().isEmpty)
    }
}

extension NestSyncTests {
    func testOfflineTaskDefinitionEditPrecedesItsExecutionAndSurvivesPlanRefresh() throws {
        let db = try database()
        var plan = DayPlan(date: .init(year: 2030, month: 10, day: 1))
        plan.revision = 1; plan.sourceRevision = 1; plan.timeZoneID = "Asia/Shanghai"
        plan.blocks = [.init(dayPlanID: plan.id, layerIndex: 0, title: "Morning", tasks: [], timing: .absolute(startMinuteOfDay: 540, requestedEndMinuteOfDay: 600))]
        plan.blocks[0].resolvedStartMinuteOfDay = 540; plan.blocks[0].resolvedEndMinuteOfDay = 600
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let remote = NestRemoteEntity(kind: "plan", id: plan.id.uuidString.lowercased(), revision: 1, deleted: false, body: try JSONDecoder().decode(NestJSON.self, from: encoder.encode(plan)))
        try db.apply(.init(cursor: "a", hasMore: false, changes: [remote]))
        _ = try db.mutate { $0.dayPlans[0].blocks[0].tasks.append(.init(title: "New offline task")) }
        _ = try db.mutate { $0.dayPlans[0].blocks[0].tasks[0].isCompleted = true; $0.dayPlans[0].blocks[0].tasks[0].completedAt = .now }
        let pending = try db.pendingOperations(), correction = try XCTUnwrap(pending.first)
        XCTAssertEqual(correction.kind, "dayCorrection")
        let execution = try XCTUnwrap(pending.last)
        XCTAssertEqual(execution.kind, "execution")
        if case let .object(value) = try JSONDecoder().decode(NestJSON.self, from: execution.payload) { XCTAssertEqual(value["correctionOperationID"], .string(correction.operationID)) }
        else { XCTFail("Missing execution payload") }
        try db.apply(.init(cursor: "b", hasMore: false, changes: [remote]))
        XCTAssertEqual(try db.load()?.dayPlans[0].blocks[0].tasks[0].title, "New offline task")
        XCTAssertEqual(try db.load()?.dayPlans[0].blocks[0].tasks[0].isCompleted, true)
    }
}

extension NestSyncTests {
    func testCachedRulesMaterializeMissingDatesWithEffectiveVersionsAndPreserveOfflineExecution() throws {
        let db = try database(), day = LocalDay(year: 2030, month: 10, day: 1)
        var template = SavedDayTemplate(title: "Cached", blocks: [.init(layerIndex: 0, title: "Original", taskBlueprints: [.init(title: "Water", order: 0)], timing: .absolute(startMinuteOfDay: 540, requestedEndMinuteOfDay: 600))])
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        func routine(_ revision: Int, effective: LocalDay) throws -> NestRemoteEntity {
            guard case var .object(body) = try JSONDecoder().decode(NestJSON.self, from: encoder.encode(template)) else { throw CocoaError(.coderInvalidValue) }
            body["effectiveFrom"] = try JSONDecoder().decode(NestJSON.self, from: encoder.encode(effective))
            return .init(kind: "routine", id: template.id.uuidString.lowercased(), revision: revision, deleted: false, body: .object(body))
        }
        let first = try routine(1, effective: day)
        template.blocks[0].title = "Next week"
        let next = try routine(2, effective: day.adding(days: 7))
        let rule = NestRemoteEntity(kind: "weekdayRule", id: String(day.weekday.rawValue), revision: 1, deleted: false, body: .object(["weekday": .number(Double(day.weekday.rawValue)), "savedTemplateID": .string(template.id.uuidString.lowercased())]))
        try db.saveScheduleCache(.init(cursor: UUID().uuidString.lowercased(), timeZoneID: "Asia/Shanghai", versions: [first, rule, next]))
        let plan = try XCTUnwrap(db.materializeCachedDay(day))
        XCTAssertEqual(plan.blocks[0].title, "Original"); XCTAssertEqual(plan.sourceRevision, 1)
        XCTAssertEqual(try db.materializeCachedDay(day)?.id, plan.id)
        XCTAssertEqual(try db.pendingOperations().map(\.kind), ["offlinePlan"])
        _ = try db.mutate { $0.dayPlans[0].blocks[0].tasks[0].isCompleted = true; $0.dayPlans[0].blocks[0].tasks[0].completedAt = .now }
        _ = try db.mutate { $0.dayPlans[0].blocks[0].tasks[0].isCompleted = false; $0.dayPlans[0].blocks[0].tasks[0].completedAt = nil }
        XCTAssertEqual(try db.pendingOperations().map(\.kind), ["offlinePlan", "execution", "execution"])
        var cloud = try TemplateEngine.instantiateDayPlan(from: template, for: day)
        cloud.revision = 1; cloud.sourceRevision = 2; cloud.timeZoneID = "Asia/Shanghai"
        let remote = NestRemoteEntity(kind: "plan", id: cloud.id.uuidString.lowercased(), revision: 1, deleted: false, body: try JSONDecoder().decode(NestJSON.self, from: encoder.encode(cloud)))
        try db.apply(.init(cursor: "after-reconnect", hasMore: false, changes: [remote]))
        XCTAssertEqual(try db.load()?.dayPlan(for: day)?.id, plan.id)
        XCTAssertEqual(try db.load()?.dayPlan(for: day)?.blocks[0].tasks[0].isCompleted, false)
        let future = try XCTUnwrap(db.materializeCachedDay(day.adding(days: 7)))
        XCTAssertEqual(future.blocks[0].title, "Next week"); XCTAssertEqual(future.sourceRevision, 2)
        let reopened = try NestLocalDatabase(url: URL(fileURLWithPath: db.databasePath), partition: db.partition)
        XCTAssertEqual(try reopened.pendingOperations().map(\.operationID), try db.pendingOperations().map(\.operationID))
        XCTAssertEqual(try reopened.load()?.dayPlan(for: day)?.id, plan.id)
    }
}

extension NestSyncTests {
    func testCorrectionConflictRebasesDependentNewTaskExecutionInOrder() throws {
        let db = try database()
        var plan = DayPlan(date: .init(year: 2030, month: 10, day: 1))
        plan.revision = 1; plan.timeZoneID = "Asia/Shanghai"
        plan.blocks = [.init(dayPlanID: plan.id, layerIndex: 0, title: "Morning", tasks: [], timing: .absolute(startMinuteOfDay: 540, requestedEndMinuteOfDay: 600))]
        plan = try DayPlanEngine.resolved(plan)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let remote = NestRemoteEntity(kind: "plan", id: plan.id.uuidString.lowercased(), revision: 1, deleted: false, body: try JSONDecoder().decode(NestJSON.self, from: encoder.encode(plan)))
        try db.apply(.init(cursor: "base", hasMore: false, changes: [remote]))
        _ = try db.mutate { $0.dayPlans[0].blocks[0].tasks.append(.init(title: "New task", isCompleted: true, completedAt: .now)) }
        let before = try db.pendingOperations(), correction = before[0], execution = before[1]
        let competing = NestRemoteEntity(kind: "dayCorrection", id: correction.entityID, revision: 1, deleted: false, body: try JSONDecoder().decode(NestJSON.self, from: correction.payload))
        try db.acknowledge([.init(operationID: correction.operationID, status: "rejected", error: "revision_conflict", details: .init(remote: competing)), .init(operationID: execution.operationID, status: "rejected", error: "unknown_correction")])
        try db.resolveDomainConflict(operationID: correction.operationID, keepLocal: true)
        let after = try db.pendingOperations()
        XCTAssertEqual(after.map(\.kind), ["dayCorrection", "execution"])
        guard case let .object(state) = try JSONDecoder().decode(NestJSON.self, from: after[1].payload) else { return XCTFail() }
        XCTAssertEqual(state["correctionOperationID"], .string(after[0].operationID))
        XCTAssertNotEqual(after[1].operationID, execution.operationID)
        XCTAssertEqual(try db.blockedOperationCount(), 0)
    }
}

extension NestSyncTests {
    func testIOSRoutineWireFixtureAndAcknowledgementPreserveLocalLineage() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("nest/contracts/ios-routine.json"))
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        var routine = try decoder.decode(SavedDayTemplate.self, from: data)
        routine.revision = 7; routine.logicalRoutineID = UUID(); routine.versionID = UUID()
        routine.parentVersionID = UUID()
        routine.provenance = .init(source: .plannerSuggestion, suggestionID: UUID(), recordedAt: routine.updatedAt)
        let db = try database()
        _ = try db.mutate { $0.savedTemplates = [routine] }
        let operation = try XCTUnwrap(db.pendingOperations().first)
        let expected = try JSONDecoder().decode(NestJSON.self, from: data)
        XCTAssertEqual(try JSONDecoder().decode(NestJSON.self, from: operation.payload), expected)
        try db.acknowledge([.init(operationID: operation.operationID, status: "accepted", revision: 1, body: expected, deleted: false)])
        XCTAssertEqual(try db.load()?.savedTemplates.first, routine)
        XCTAssertTrue(try db.pendingOperations().isEmpty)
        var metadataOnly = routine; metadataOnly.provenance = .init(source: .local)
        XCTAssertTrue(try NestLocalChanges.between(.init(savedTemplates: [routine]), .init(savedTemplates: [metadataOnly])).isEmpty)

        guard case var .object(changed) = expected else { return XCTFail("Expected routine object") }
        changed["title"] = .string("Changed remotely")
        let entity = NestRemoteEntity(kind: "routine", id: routine.id.uuidString.lowercased(), revision: 2, deleted: false, body: .object(changed))
        try db.apply(.init(cursor: "remote-change", hasMore: false, changes: [entity]))
        let document = try XCTUnwrap(db.load()), updated = try XCTUnwrap(document.savedTemplates.first)
        XCTAssertEqual(updated.revision, 8); XCTAssertEqual(updated.logicalRoutineID, routine.logicalRoutineID)
        XCTAssertEqual(updated.parentVersionID, routine.versionID); XCTAssertNotEqual(updated.versionID, routine.versionID)
        XCTAssertNil(updated.provenance); XCTAssertEqual(document.routineRevisionSnapshots.first?.provenance, routine.provenance)
        try db.apply(.init(cursor: "remote-repeat", hasMore: false, changes: [entity]))
        XCTAssertEqual(try db.load()?.routineRevisionSnapshots.count, 1)
        XCTAssertEqual(try db.load()?.savedTemplates.first?.versionID, updated.versionID)
    }

    func testLoginCallbackRejectsWrongRouteIssuerStateAndDuplicateValues() throws {
        let issuer = URL(string: "https://nest.example.com")!
        let valid = "top.protium.samoyed:/oauth/callback?state=expected&iss=https%3A%2F%2Fnest.example.com&code=one"
        XCTAssertEqual(try NestLoginCallback.code(from: URL(string: valid)!, state: "expected", issuer: issuer), "one")
        for invalid in [
            valid.replacingOccurrences(of: "top.protium.samoyed:", with: "samoyed:"),
            valid.replacingOccurrences(of: ":/oauth", with: "://attacker/oauth"),
            valid.replacingOccurrences(of: "/oauth/callback", with: "/oauth/other"),
            valid.replacingOccurrences(of: "state=expected", with: "state=wrong"),
            valid.replacingOccurrences(of: "nest.example.com", with: "attacker.example.com"),
            valid + "&state=expected", valid + "&iss=https%3A%2F%2Fnest.example.com", valid + "&code=two",
            valid + "#fragment", valid.replacingOccurrences(of: "code=one", with: "code=")
        ] { XCTAssertThrowsError(try NestLoginCallback.code(from: URL(string: invalid)!, state: "expected", issuer: issuer), invalid) }
    }
}

extension NestSyncTests {
    func testChoosingRemoteRoutineConflictArchivesFullLocalLineage() throws {
        let db = try database()
        var local = SavedDayTemplate(title: "Planner version", blocks: [], revision: 6, versionID: UUID(), parentVersionID: UUID(), provenance: .init(source: .plannerSuggestion, suggestionID: UUID()))
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        func body(_ routine: SavedDayTemplate) throws -> NestJSON {
            try JSONDecoder().decode(NestJSON.self, from: encoder.encode(NestRoutinePayload(routine)))
        }
        _ = try db.mutate { $0.savedTemplates = [local] }
        let first = try XCTUnwrap(db.pendingOperations().first)
        try db.acknowledge([.init(operationID: first.operationID, status: "accepted", revision: 1, body: try body(local), deleted: false)])
        local.title = "Pending local version"
        _ = try db.mutate { $0.savedTemplates = [local] }
        let operation = try XCTUnwrap(db.pendingOperations().first)
        var remote = local; remote.title = "Remote choice"
        let entity = NestRemoteEntity(kind: "routine", id: local.id.uuidString.lowercased(), revision: 2, deleted: false, body: try body(remote))
        try db.acknowledge([.init(operationID: operation.operationID, status: "rejected", error: "revision_conflict", details: .init(remote: entity))])
        try db.resolveDomainConflict(operationID: operation.operationID, keepLocal: false)
        let document = try XCTUnwrap(db.load()), routine = try XCTUnwrap(document.savedTemplates.first)
        XCTAssertEqual(routine.title, "Remote choice"); XCTAssertEqual(routine.logicalRoutineID, local.logicalRoutineID)
        XCTAssertEqual(routine.parentVersionID, local.versionID); XCTAssertEqual(routine.revision, 7)
        XCTAssertNil(routine.provenance)
        XCTAssertEqual(document.routineRevisionSnapshots.first?.provenance, local.provenance)
        XCTAssertEqual(document.routineRevisionSnapshots.first?.title, local.title)
    }
}

extension NestSyncTests {
    func testDiscardedRoutineCreationArchivesPlannerLineage() throws {
        let db = try database()
        let local = SavedDayTemplate(title: "Rejected creation", blocks: [], revision: 4, versionID: UUID(), provenance: .init(source: .plannerSuggestion, suggestionID: UUID()))
        _ = try db.mutate { $0.savedTemplates = [local] }
        let operation = try XCTUnwrap(db.pendingOperations().first)
        try db.acknowledge([.init(operationID: operation.operationID, status: "rejected", error: "invalid_payload")])
        try db.resolveDomainConflict(operationID: operation.operationID, keepLocal: false)
        XCTAssertTrue(try db.load()?.savedTemplates.isEmpty == true)
        struct Archive: Decodable { var localRoutine: SavedDayTemplate? }
        let archived = try db.queue.read { db in
            try Data.fetchAll(db, sql: "SELECT body FROM migration_archive WHERE id LIKE 'conflict-%'")
        }
        let saved = try archived.map { try JSONDecoder().decode(Archive.self, from: $0) }
        XCTAssertEqual(saved.first?.localRoutine, local)
    }
}
