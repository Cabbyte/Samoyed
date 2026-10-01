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
