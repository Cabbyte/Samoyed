import Foundation
import XCTest
@testable import SamoyedCore

final class NestPersistenceTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    func testMigrationPreservesOriginalAndDoesNotReplayOldJSON() throws {
        let dir = try directory(), legacy = dir.appendingPathComponent("document.json")
        let note = TimelineNote(text: "Backdated", occurredAt: Date(timeIntervalSince1970: 1234))
        let document = SamoyedDocument(timelineNotes: [note])
        let original = try JSONEncoder().encode(document); try original.write(to: legacy)
        let repo = SamoyedDocumentRepository(fileURL: legacy)
        XCTAssertEqual(try repo.load(), document)
        XCTAssertEqual(try Data(contentsOf: legacy), original)
        XCTAssertEqual(try Data(contentsOf: legacy.appendingPathExtension("pre-nest-backup")), original)
        _ = try repo.mutate { $0.timelineNotes[0].text = "Changed" }
        XCTAssertEqual(try SamoyedDocumentRepository(fileURL: legacy).load()?.timelineNotes[0].text, "Changed")
        XCTAssertEqual(try Data(contentsOf: legacy), original)
    }
    func testFailedMutationRollsBackDocumentAndOutbox() throws {
        let db = try NestLocalDatabase(url: directory().appendingPathComponent("test.sqlite"), partition: "instance/user")
        enum Failed: Error { case expected }
        XCTAssertThrowsError(try db.mutate { doc in doc.timelineNotes.append(TimelineNote(text: "Uncommitted")); throw Failed.expected })
        XCTAssertNil(try db.load()); XCTAssertTrue(try db.pendingOperations().isEmpty)
    }
    func testPartitionsAndDurableOutboxOrdering() throws {
        let url = try directory().appendingPathComponent("test.sqlite")
        let a = try NestLocalDatabase(url: url, partition: "one/alice")
        let b = try NestLocalDatabase(url: url, partition: "one/bob")
        let otherNest = try NestLocalDatabase(url: url, partition: "two/alice")
        let local = try NestLocalDatabase(url: url)
        _ = try a.mutate { $0.timelineNotes.append(TimelineNote(text: "First")) }
        _ = try a.mutate { $0.timelineNotes[0].text = "Second" }
        let restarted = try NestLocalDatabase(url: url, partition: "one/alice")
        let pending = try restarted.pendingOperations()
        XCTAssertEqual(pending.map(\.expectedRevision), [0, 1]); XCTAssertNotEqual(pending[0].operationID, pending[1].operationID)
        XCTAssertNil(try b.load()); XCTAssertNil(try otherNest.load()); XCTAssertNil(try local.load())
        XCTAssertEqual(try restarted.load()?.timelineNotes[0].text, "Second")
    }
    func testNotesSurviveRoutineDeletionAndSortByOccurredTime() throws {
        let day = LocalDay(year: 2026, month: 10, day: 1)
        let early = TimelineNote(text: "Afternoon, entered at night", occurredAt: try NestTimeResolver.instant(on: day, minute: 900, timeZoneID: "Asia/Shanghai"), blockInstanceID: UUID())
        let late = TimelineNote(text: "Night", occurredAt: early.occurredAt.addingTimeInterval(3600))
        var doc = SamoyedDocument(timelineNotes: [late, early])
        doc.savedTemplates.removeAll(); doc.dayPlans.removeAll()
        XCTAssertEqual(doc.timelineNotes(on: day, timeZone: TimeZone(identifier: "Asia/Shanghai")!).map(\.id), [early.id, late.id])
    }
    func testSharedDSTFixtures() throws {
        struct Fixture: Decodable { var name: String; var date: LocalDay; var minute: Int; var timeZoneID: String; var instant: String }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let cases = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: root.appendingPathComponent("nest/contracts/time-cases.json")))
        for item in cases {
            XCTAssertEqual(try NestTimeResolver.instant(on: item.date, minute: item.minute, timeZoneID: item.timeZoneID), ISO8601DateFormatter().date(from: item.instant), item.name)
        }
    }
}

extension NestPersistenceTests {
    func testStaleDocumentSavePreservesUnrelatedWriterAndRejectsSameObject() throws {
        let initial = SamoyedDocument(timelineNotes: [TimelineNote(text: "Original")])
        var extensionWrite = initial
        extensionWrite.timelineNotes.append(TimelineNote(text: "Extension note"))
        var appWrite = initial
        appWrite.timelineNotes[0].text = "App edit"
        let merged = try NestDocumentMerge.merge(base: initial, proposed: appWrite, latest: extensionWrite)
        XCTAssertEqual(Set(merged.timelineNotes.map(\.text)), ["App edit", "Extension note"])
        extensionWrite.timelineNotes[0].text = "Concurrent edit"
        XCTAssertThrowsError(try NestDocumentMerge.merge(base: initial, proposed: appWrite, latest: extensionWrite))
    }
}

extension NestPersistenceTests {
    func testSQLiteBackupRestoreKeepsPendingWritesAndPartitions() throws {
        let directory = try directory()
        let source = try NestLocalDatabase(url: directory.appendingPathComponent("source.sqlite"), partition: "nest/alice")
        let destination = try NestLocalDatabase(url: directory.appendingPathComponent("backup.sqlite"), partition: "nest/alice")
        _ = try source.mutate { $0.timelineNotes.append(TimelineNote(text: "Pending offline note")) }
        let operations = try source.pendingOperations()
        try source.queue.backup(to: destination.queue)
        XCTAssertEqual(try destination.load(), try source.load())
        XCTAssertEqual(try destination.pendingOperations(), operations)
        let bob = try NestLocalDatabase(url: directory.appendingPathComponent("backup.sqlite"), partition: "nest/bob")
        XCTAssertNil(try bob.load())
    }
}

extension NestPersistenceTests {
    func testIntegratedDocumentRoundTripAndStaleSavePreserveAllDomainFields() throws {
        let day = LocalDay(year: 2026, month: 10, day: 1)
        var plan = DayPlan(date: day)
        plan.source = "nest"; plan.sourceCursor = "cursor"; plan.sourceRevision = 4; plan.revision = 8; plan.timeZoneID = "Asia/Shanghai"
        var task = TaskItem(title: "Task"); task.sourceTaskID = UUID()
        var block = TimeBlock(layerIndex: 0, title: "Block", tasks: [task], timing: .absolute(startMinuteOfDay: 0, requestedEndMinuteOfDay: 60))
        block.sourceBlockID = UUID(); plan.blocks = [block]
        let routine = SavedDayTemplate(title: "Versioned", blocks: [], revision: 4, versionID: UUID(), parentVersionID: UUID(), provenance: .init(source: .imported))
        let feedback = FeedbackEvent(target: .wholeDay, localDay: day, sentiment: .good, source: .today)
        let suggestion = Suggestion(kind: .routineImprovement, title: "Review")
        let snapshot = RoutineRevisionSnapshot(routineID: routine.id, logicalRoutineID: routine.logicalRoutineID, revision: routine.revision, versionID: routine.versionID, parentVersionID: routine.parentVersionID, title: routine.title, blocks: routine.blocks, createdAt: routine.updatedAt, provenance: routine.provenance)
        let document = SamoyedDocument(dayPlans: [plan], savedTemplates: [routine], feedbackEvents: [feedback], suggestions: [suggestion], routineRevisionSnapshots: [snapshot], plannerSettings: .init(connectionState: .needsAttention), timelineNotes: [.init(text: "Note")])
        let repo = SamoyedDocumentRepository(fileURL: try directory().appendingPathComponent("document.json"))
        try repo.save(document)
        XCTAssertEqual(try repo.load(), document)
        let base = document
        var latest = base; latest.timelineNotes.append(.init(text: "Concurrent note"))
        var proposed = base
        proposed.feedbackEvents.append(.init(target: .wholeDay, localDay: day, sentiment: .tired, source: .now))
        proposed.suggestions[0].lifecycleState = .rejected
        proposed.routineRevisionSnapshots.append(.init(routineID: routine.id, logicalRoutineID: routine.logicalRoutineID, revision: 5, versionID: UUID(), parentVersionID: routine.versionID, title: "New version", blocks: [], createdAt: .now, provenance: nil))
        proposed.plannerSettings.connectionState = .unavailable
        let merged = try NestDocumentMerge.merge(base: base, proposed: proposed, latest: latest)
        XCTAssertEqual(merged.timelineNotes, latest.timelineNotes)
        XCTAssertEqual(merged.feedbackEvents, proposed.feedbackEvents)
        XCTAssertEqual(merged.suggestions, proposed.suggestions)
        XCTAssertEqual(merged.routineRevisionSnapshots, proposed.routineRevisionSnapshots)
        XCTAssertEqual(merged.plannerSettings, proposed.plannerSettings)
        latest.plannerSettings.connectionState = .connected
        XCTAssertThrowsError(try NestDocumentMerge.merge(base: base, proposed: proposed, latest: latest))
    }

    func testScopedRuntimeServicesCannotWriteIntoAnotherAccount() throws {
        let repo = SamoyedDocumentRepository(fileURL: try directory().appendingPathComponent("document.json"))
        let a = NestAccountPartition(instanceID: "instance:a", userID: "alice")
        let b = NestAccountPartition(instanceID: "instance", userID: "a:alice")
        XCTAssertNotEqual(a.key, b.key)
        let first = repo.scoped(to: a.key), second = repo.scoped(to: b.key)
        let feedback = FeedbackEvent(target: .wholeDay, localDay: .init(year: 2026, month: 10, day: 1), sentiment: .good, source: .today)
        _ = try FeedbackService(repository: first).save(feedback)
        XCTAssertEqual(try first.load()?.feedbackEvents, [feedback])
        XCTAssertNil(try second.load()); XCTAssertNil(try repo.load())
        _ = try FeedbackService(repository: second).save(feedback)
        XCTAssertEqual(try first.load()?.feedbackEvents.count, 1)
        XCTAssertEqual(try second.load()?.feedbackEvents.count, 1)
    }
}
