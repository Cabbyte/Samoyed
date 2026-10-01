import Foundation
import GRDB

struct NestOutboxOperation: Codable, Equatable, Sendable {
    var operationID: String
    var kind: String
    var entityID: String
    var expectedRevision: Int
    var payload: Data
    var deleted: Bool
}

/// One database for the App Group. Every durable row is scoped to an account partition.
/// GRDB serializes writers across processes using SQLite transactions and busy_timeout.
final class NestLocalDatabase {
    let queue: DatabaseQueue
    let partition: String
    var databasePath: String { queue.path }

    init(url: URL, partition: String = "local", legacyURL: URL? = nil) throws {
        self.partition = partition
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var configuration = Configuration()
        configuration.busyMode = .timeout(5)
        queue = try DatabaseQueue(path: url.path, configuration: configuration)
        var migrator = DatabaseMigrator()
        migrator.registerMigration("nest-local-v1") { db in
            try db.execute(sql: """
                CREATE TABLE documents (partition TEXT PRIMARY KEY, body BLOB NOT NULL);
                CREATE TABLE outbox (
                    sequence INTEGER PRIMARY KEY AUTOINCREMENT, partition TEXT NOT NULL,
                    operationID TEXT NOT NULL UNIQUE, kind TEXT NOT NULL, entityID TEXT NOT NULL,
                    expectedRevision INTEGER NOT NULL, payload BLOB NOT NULL, deleted INTEGER NOT NULL,
                    status TEXT NOT NULL DEFAULT 'pending');
                CREATE INDEX outbox_partition_sequence ON outbox(partition, sequence);
                CREATE TABLE remote_entities (partition TEXT NOT NULL, kind TEXT NOT NULL, entityID TEXT NOT NULL,
                    revision INTEGER NOT NULL, body BLOB NOT NULL, deleted INTEGER NOT NULL,
                    PRIMARY KEY (partition, kind, entityID));
                CREATE TABLE sync_state (partition TEXT PRIMARY KEY, cursor TEXT);
                CREATE TABLE conflicts (partition TEXT NOT NULL, operationID TEXT NOT NULL, local BLOB NOT NULL,
                    remote BLOB NOT NULL, PRIMARY KEY(partition, operationID));
                CREATE TABLE migration_archive (id TEXT PRIMARY KEY, body BLOB NOT NULL, createdAt REAL NOT NULL);
                """)
        }
        migrator.registerMigration("nest-conflict-reason-v2") { db in
            try db.execute(sql: "ALTER TABLE conflicts ADD COLUMN reason TEXT NOT NULL DEFAULT 'revision_conflict'")
        }
        migrator.registerMigration("nest-schedule-cache-v3") { db in
            try db.execute(sql: "CREATE TABLE schedule_cache(partition TEXT PRIMARY KEY, body BLOB NOT NULL)")
        }
        try migrator.migrate(queue)
        if let legacyURL, partition == "local", FileManager.default.fileExists(atPath: legacyURL.path) {
            try queue.write { db in
                guard try Data.fetchOne(db, sql: "SELECT body FROM documents WHERE partition = ?", arguments: [partition]) == nil else { return }
                let original = try Data(contentsOf: legacyURL)
                let document = try JSONDecoder().decode(SamoyedDocument.self, from: original)
                // Validate a full round-trip, including IDs, dates, checklist states and optional content.
                let migrated = try JSONEncoder().encode(document)
                guard try JSONDecoder().decode(SamoyedDocument.self, from: migrated) == document else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                let backup = legacyURL.appendingPathExtension("pre-nest-backup")
                if !FileManager.default.fileExists(atPath: backup.path) {
                    try original.write(to: backup, options: .atomic)
                }
                try db.execute(sql: "INSERT INTO migration_archive VALUES (?, ?, ?)", arguments: ["legacy-json", original, Date().timeIntervalSince1970])
                try db.execute(sql: "INSERT INTO documents VALUES (?, ?)", arguments: [partition, migrated])
            }
        }
    }

    func load() throws -> SamoyedDocument? {
        try queue.read { db in
            try Self.read(db, partition: partition)
        }
    }

    func importLocal(_ source: SamoyedDocument) throws {
        guard partition != "local" else { throw CocoaError(.coderInvalidValue) }
        try queue.write { db in
            try db.execute(sql: "INSERT OR IGNORE INTO migration_archive VALUES(?,?,?)", arguments: ["import-" + partition, try JSONEncoder().encode(source), Date().timeIntervalSince1970])
        }
        _ = try mutate { document in
            for template in source.savedTemplates where !document.savedTemplates.contains(where: { $0.id == template.id }) { document.savedTemplates.append(template) }
            for rule in source.weekdayRules where !document.weekdayRules.contains(where: { $0.weekday == rule.weekday }) { document.weekdayRules.append(rule) }
            for override in source.overrides where !document.overrides.contains(where: { $0.date == override.date }) { document.overrides.append(override) }
            for var plan in source.dayPlans where !document.dayPlans.contains(where: { $0.date == plan.date }) {
                plan.source = "legacy"; document.dayPlans.append(plan)
            }
            for var note in source.timelineNotes where !document.timelineNotes.contains(where: { $0.id == note.id }) && note.deletedAt == nil {
                note.source = "legacy"; note.revision = 0; document.timelineNotes.append(note)
            }
        }
    }

    func mutate<Value>(_ body: (inout SamoyedDocument) throws -> Value) throws -> SamoyedDocumentRepository.MutationOutcome<Value> {
        try queue.write { db in
            let current = try Self.read(db, partition: partition) ?? SamoyedDocument()
            var updated = current
            let value = try body(&updated)
            if updated != current {
                let data = try JSONEncoder().encode(updated)
                try db.execute(sql: "INSERT INTO documents VALUES (?, ?) ON CONFLICT(partition) DO UPDATE SET body=excluded.body", arguments: [partition, data])
                // Local-only history stays local. Binding imports explicitly into a new partition.
                if partition != "local" {
                    for change in try NestLocalChanges.between(current, updated) {
                        let pendingRevision = try Int.fetchOne(db, sql: "SELECT expectedRevision + 1 FROM outbox WHERE partition=? AND kind=? AND entityID=? ORDER BY sequence DESC LIMIT 1", arguments: [partition, change.kind, change.entityID])
                        let remoteRevision = try Int.fetchOne(db, sql: "SELECT revision FROM remote_entities WHERE partition=? AND kind=? AND entityID=?", arguments: [partition, change.kind, change.entityID]) ?? 0
                        var payload = change.payload
                        if change.kind == "execution", case var .object(state) = try JSONDecoder().decode(NestJSON.self, from: payload), case let .string(blockID)? = state["blockInstanceID"],
                           let correction = try String.fetchOne(db, sql: "SELECT operationID FROM outbox WHERE partition=? AND kind='dayCorrection' AND entityID=? ORDER BY sequence DESC LIMIT 1", arguments: [partition, blockID.lowercased()]) {
                            state["correctionOperationID"] = .string(correction); payload = try JSONEncoder().encode(NestJSON.object(state))
                        }
                        try db.execute(sql: "INSERT INTO outbox(partition,operationID,kind,entityID,expectedRevision,payload,deleted,status) VALUES (?,?,?,?,?,?,?,CASE WHEN EXISTS(SELECT 1 FROM outbox WHERE partition=? AND kind=? AND entityID=? AND status='conflict') THEN 'conflict' ELSE 'pending' END)", arguments: [partition, UUID().uuidString.lowercased(), change.kind, change.entityID, pendingRevision ?? remoteRevision, payload, change.deleted, partition, change.kind, change.entityID])
                    }
                }
            }
            return .init(value: value, changed: current != updated, document: updated)
        }
    }

    func blockedOperationCount() throws -> Int {
        try queue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM outbox WHERE partition=? AND status='conflict'", arguments: [partition]) ?? 0
        }
    }

    func pendingOperations() throws -> [NestOutboxOperation] {
        try queue.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM outbox WHERE partition=? AND status='pending' ORDER BY sequence", arguments: [partition]).map {
                .init(operationID: $0["operationID"], kind: $0["kind"], entityID: $0["entityID"], expectedRevision: $0["expectedRevision"], payload: $0["payload"], deleted: $0["deleted"])
            }
        }
    }

    private static func read(_ db: Database, partition: String) throws -> SamoyedDocument? {
        guard let data = try Data.fetchOne(db, sql: "SELECT body FROM documents WHERE partition=?", arguments: [partition]) else { return nil }
        return try JSONDecoder().decode(SamoyedDocument.self, from: data)
    }
}

struct NestLocalChanges {
    struct Change { var kind: String; var entityID: String; var payload: Data; var deleted: Bool }
    static func between(_ before: SamoyedDocument, _ after: SamoyedDocument) throws -> [Change] {
        // Each object is uploaded independently. No whole-document replacement enters the protocol.
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.sortedKeys]
        var result: [Change] = []
        func diff<T: Encodable & Equatable>(_ old: [T], _ new: [T], kind: String, id: (T) -> String, deleted: (T) -> Bool = { _ in false }) throws {
            let oldMap = Dictionary(uniqueKeysWithValues: old.map { (id($0), $0) })
            let newMap = Dictionary(uniqueKeysWithValues: new.map { (id($0), $0) })
            for item in new where oldMap[id(item)] != item {
                result.append(.init(kind: kind, entityID: id(item), payload: try encoder.encode(item), deleted: deleted(item)))
            }
            for item in old where newMap[id(item)] == nil {
                result.append(.init(kind: kind, entityID: id(item), payload: try encoder.encode(item), deleted: true))
            }
        }
        try diff(before.timelineNotes, after.timelineNotes, kind: "note", id: { $0.id.uuidString.lowercased() }, deleted: { $0.deletedAt != nil })
        try diff(before.savedTemplates, after.savedTemplates, kind: "routine", id: { $0.id.uuidString.lowercased() })
        for plan in after.dayPlans {
            if plan.source == "offline", !before.dayPlans.contains(where: { $0.id == plan.id }) {
                result.append(.init(kind: "offlinePlan", entityID: plan.id.uuidString.lowercased(), payload: try encoder.encode(plan), deleted: false))
            }
            if plan.source == "legacy", !before.dayPlans.contains(where: { $0.id == plan.id }) {
                result.append(.init(kind: "legacyPlan", entityID: plan.id.uuidString.lowercased(), payload: try encoder.encode(plan), deleted: false))
            }
            guard let revision = plan.revision else { continue } // Legacy data requires explicit import.
            let zone = plan.timeZoneID ?? TimeZone.current.identifier
            let oldPlan = before.dayPlans.first { $0.id == plan.id }
            for block in plan.blocks {
                let oldBlock = oldPlan?.blocks.first { $0.id == block.id }
                let taskDefinitions = block.tasks.map { NestTaskDefinition($0) }
                if let oldBlock, oldBlock.timing != block.timing || oldBlock.title != block.title || oldBlock.note != block.note || oldBlock.tasks.map({ NestTaskDefinition($0) }) != taskDefinitions {
                    struct Correction: Encodable {
                        var date: LocalDay; var planID: UUID; var planRevision: Int; var blockInstanceID: UUID
                        var startMinuteOfDay: Int; var endMinuteOfDay: Int; var title: String; var note: NestJSON; var tasks: [NestTaskDefinition]
                    }
                    if let start = block.resolvedStartMinuteOfDay, let end = block.resolvedEndMinuteOfDay {
                        result.append(.init(kind: "dayCorrection", entityID: block.id.uuidString.lowercased(), payload: try encoder.encode(Correction(date: plan.date, planID: plan.id, planRevision: revision, blockInstanceID: block.id, startMinuteOfDay: start, endMinuteOfDay: end, title: block.title, note: block.note.map(NestJSON.string) ?? .null, tasks: taskDefinitions)), deleted: false))
                    }
                }
                for task in block.tasks {
                    let oldTask = oldBlock?.tasks.first { $0.id == task.id }
                    guard oldTask?.isCompleted != task.isCompleted || oldTask?.completedAt != task.completedAt else { continue }
                    struct State: Encodable {
                        var planID: UUID; var planRevision: Int; var blockInstanceID: UUID; var taskInstanceID: UUID
                        var isCompleted: Bool; var occurredAt: Date; var timeZoneID: String; var source = "ios"
                    }
                    result.append(.init(kind: "execution", entityID: task.id.uuidString.lowercased(), payload: try encoder.encode(State(planID: plan.id, planRevision: revision, blockInstanceID: block.id, taskInstanceID: task.id, isCompleted: task.isCompleted, occurredAt: task.completedAt ?? .now, timeZoneID: zone)), deleted: false))
                }
            }
        }
        // Rules and selections are keyed by their stable business identity, not titles.
        try diff(before.weekdayRules, after.weekdayRules, kind: "weekdayRule", id: { String($0.weekday.rawValue) })
        func choices(_ document: SamoyedDocument) -> [String: NestJSON] {
            var result: [String: NestJSON] = [:]
            func insert(_ date: LocalDay, _ template: UUID?) {
                let key = String(format: "%04d-%02d-%02d", date.year, date.month, date.day)
                result[key] = .object(["date": .object(["year": .number(Double(date.year)), "month": .number(Double(date.month)), "day": .number(Double(date.day))]), "savedTemplateID": template.map { .string($0.uuidString.lowercased()) } ?? .null])
            }
            for value in document.overrides { insert(value.date, value.savedTemplateID) }
            for value in document.daySelections.sorted(by: { $0.selectedAt < $1.selectedAt }) { insert(value.date, value.selectedTemplateID) }
            return result
        }
        let oldChoices = choices(before), newChoices = choices(after)
        for id in Set(oldChoices.keys).union(newChoices.keys).sorted() where oldChoices[id] != newChoices[id] {
            result.append(.init(kind: "dateException", entityID: id, payload: try encoder.encode(newChoices[id] ?? .null), deleted: newChoices[id] == nil))
        }

        let order = ["routine": 0, "weekdayRule": 1, "dateException": 2, "legacyPlan": 3, "offlinePlan": 3, "note": 4, "dayCorrection": 5, "execution": 6]
        return result.sorted { order[$0.kind, default: 6] < order[$1.kind, default: 6] }
    }
}

extension NestLocalDatabase {
    func saveScheduleCache(_ cache: NestScheduleCache) throws {
        try queue.write { db in
            try db.execute(sql: "INSERT INTO schedule_cache VALUES(?,?) ON CONFLICT(partition) DO UPDATE SET body=excluded.body", arguments: [partition, try JSONEncoder().encode(cache)])
        }
    }

    /// Materialize a missing date from the last confirmed version history, never
    /// from a latest template whose effective date may still be in the future.
    func materializeCachedDay(_ date: LocalDay) throws -> DayPlan? {
        guard partition != "local" else { return nil }
        return try queue.write { db in
            var document = try readDocument(db)
            if let existing = document.dayPlan(for: date) { return existing }
            guard let bytes = try Data.fetchOne(db, sql: "SELECT body FROM schedule_cache WHERE partition=?", arguments: [partition]) else { return nil }
            let cache = try JSONDecoder().decode(NestScheduleCache.self, from: bytes)
            var active: [String: NestRemoteEntity] = [:]
            for version in cache.versions {
                if case let .object(body) = version.body, let raw = body["effectiveFrom"], raw != .null,
                   try JSONDecoder().decode(LocalDay.self, from: JSONEncoder().encode(raw)) > date { continue }
                let key = version.kind + ":" + version.id.lowercased()
                active[key] = version.deleted ? nil : version
            }
            let dayKey = String(format: "%04d-%02d-%02d", date.year, date.month, date.day)
            guard let selection = active["dateException:" + dayKey] ?? active["weekdayRule:" + String(date.weekday.rawValue)],
                  case let .object(choice) = selection.body, case let .string(templateID)? = choice["savedTemplateID"],
                  let version = active["routine:" + templateID.lowercased()] else { return nil }
            let decoder = Self.wireDecoder()
            // The wire contract calls fixed instructions guidance; old files use note.
            var body = version.body
            if case var .object(object) = body, case let .array(blocks)? = object["blocks"] {
                object["blocks"] = .array(blocks.map { block in
                    guard case var .object(fields) = block else { return block }
                    if let guidance = fields["guidance"], guidance != .null { fields["note"] = guidance }
                    return .object(fields)
                }); body = .object(object)
            }
            let template = try decoder.decode(SavedDayTemplate.self, from: JSONEncoder().encode(body))
            var plan = try TemplateEngine.instantiateDayPlan(from: template, for: date)
            plan.blocks.removeAll { $0.kind == .blankBase }
            plan.source = "offline"; plan.sourceCursor = cache.cursor; plan.sourceRevision = version.revision
            plan.revision = 1; plan.timeZoneID = cache.timeZoneID
            document.dayPlans.append(plan)
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            try db.execute(sql: "INSERT INTO outbox(partition,operationID,kind,entityID,expectedRevision,payload,deleted) VALUES(?,?,?,?,?,?,0)", arguments: [partition, UUID().uuidString.lowercased(), "offlinePlan", plan.id.uuidString.lowercased(), 0, try encoder.encode(plan)])
            try store(document, db: db)
            return plan
        }
    }

    func cursor() throws -> String? {
        try queue.read { try String.fetchOne($0, sql: "SELECT cursor FROM sync_state WHERE partition=?", arguments: [partition]) }
    }

    /// Snapshot application, remote base rows and cursor advance commit together.
    /// Local entities with queued edits are left untouched until acknowledgement or conflict resolution.
    func apply(_ page: NestPullPage) throws {
        try queue.write { db in
            var document = try readDocument(db)
            for entity in page.changes { try applyRemote(entity, to: &document, db: db) }
            try projectCorrections(to: &document, db: db)
            try projectExecutions(to: &document, db: db)
            try store(document, db: db)
            try db.execute(sql: "INSERT INTO sync_state VALUES(?,?) ON CONFLICT(partition) DO UPDATE SET cursor=excluded.cursor", arguments: [partition, page.cursor])
        }
    }

    func acknowledge(_ results: [NestPushResult]) throws {
        try queue.write { db in
            var document = try readDocument(db)
            for result in results {
                guard let row = try Row.fetchOne(db, sql: "SELECT * FROM outbox WHERE partition=? AND operationID=?", arguments: [partition, result.operationID]) else { continue }
                let kind: String = row["kind"], id: String = row["entityID"]
                if result.status == "accepted", let revision = result.revision, let body = result.body {
                    try db.execute(sql: "DELETE FROM outbox WHERE partition=? AND operationID=?", arguments: [partition, result.operationID])
                    try applyRemote(.init(kind: kind, id: id, revision: revision, deleted: result.deleted ?? false, body: body), to: &document, db: db)
                } else if result.status == "rejected" {
                    // Block this entity's dependent commands, leaving unrelated entities syncable.
                    try db.execute(sql: "UPDATE outbox SET status='conflict' WHERE partition=? AND kind=? AND entityID=?", arguments: [partition, kind, id])
                    let payload: Data = row["payload"]
                    let remote = try JSONEncoder().encode(result.details?.remote)
                    try db.execute(sql: "INSERT INTO conflicts(partition,operationID,local,remote,reason) VALUES(?,?,?,?,?) ON CONFLICT(partition,operationID) DO UPDATE SET remote=excluded.remote,reason=excluded.reason", arguments: [partition, result.operationID, payload, remote, result.error ?? "rejected"])
                }
            }
            try projectCorrections(to: &document, db: db)
            try projectExecutions(to: &document, db: db)
            try store(document, db: db)
        }
    }

    private func readDocument(_ db: Database) throws -> SamoyedDocument {
        let data = try Data.fetchOne(db, sql: "SELECT body FROM documents WHERE partition=?", arguments: [partition])
        return try data.map { try JSONDecoder().decode(SamoyedDocument.self, from: $0) } ?? SamoyedDocument()
    }
    private func projectExecutions(to document: inout SamoyedDocument, db: Database) throws {
        let remote = try Data.fetchAll(db, sql: "SELECT body FROM remote_entities WHERE partition=? AND kind='execution' AND deleted=0", arguments: [partition])
        let local = try Data.fetchAll(db, sql: "SELECT payload FROM outbox WHERE partition=? AND kind='execution' ORDER BY sequence", arguments: [partition])
        struct State: Decodable { var planID: UUID; var blockInstanceID: UUID; var taskInstanceID: UUID; var isCompleted: Bool; var occurredAt: String }
        for data in remote + local {
            let state = try JSONDecoder().decode(State.self, from: data)
            if !document.dayPlans.contains(where: { $0.id == state.planID }),
               let snapshot = try Data.fetchOne(db, sql: "SELECT body FROM remote_entities WHERE partition=? AND kind='offlinePlan' AND entityID=?", arguments: [partition, state.planID.uuidString.lowercased()]) {
                let plan = try Self.wireDecoder().decode(DayPlan.self, from: snapshot)
                document.dayPlans.removeAll { $0.date == plan.date }; document.dayPlans.append(plan)
            }
            if let p = document.dayPlans.firstIndex(where: { $0.id == state.planID }),
               let b = document.dayPlans[p].blocks.firstIndex(where: { $0.id == state.blockInstanceID }),
               let t = document.dayPlans[p].blocks[b].tasks.firstIndex(where: { $0.id == state.taskInstanceID }) {
                let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                let fractional = formatter.date(from: state.occurredAt); formatter.formatOptions = [.withInternetDateTime]
                document.dayPlans[p].blocks[b].tasks[t].isCompleted = state.isCompleted
                document.dayPlans[p].blocks[b].tasks[t].completedAt = state.isCompleted ? (fractional ?? formatter.date(from: state.occurredAt)) : nil
            }
        }
    }
    private func hasExecution(_ planID: UUID, db: Database) throws -> Bool {
        let rows = try Data.fetchAll(db, sql: "SELECT body FROM remote_entities WHERE partition=? AND kind='execution' UNION ALL SELECT payload FROM outbox WHERE partition=? AND kind='execution'", arguments: [partition, partition])
        struct State: Decodable { var planID: UUID }
        return try rows.contains { try JSONDecoder().decode(State.self, from: $0).planID == planID }
    }
    private static func wireDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: text) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: text) else { throw CocoaError(.coderInvalidValue) }
            return date
        }
        return decoder
    }
    private func projectCorrections(to document: inout SamoyedDocument, db: Database) throws {
        let remote = try Data.fetchAll(db, sql: "SELECT body FROM remote_entities WHERE partition=? AND kind='dayCorrection' AND deleted=0", arguments: [partition])
        let rows = remote + (try Data.fetchAll(db, sql: "SELECT payload FROM outbox WHERE partition=? AND kind='dayCorrection' ORDER BY sequence", arguments: [partition]))
        struct Correction: Decodable { var planID: UUID; var blockInstanceID: UUID; var startMinuteOfDay: Int; var endMinuteOfDay: Int; var title: String?; var note: String?; var tasks: [NestTaskDefinition]? }
        for data in rows {
            let c = try JSONDecoder().decode(Correction.self, from: data)
            if let p = document.dayPlans.firstIndex(where: { $0.id == c.planID }), let b = document.dayPlans[p].blocks.firstIndex(where: { $0.id == c.blockInstanceID }) {
                document.dayPlans[p].blocks[b].resolvedStartMinuteOfDay = c.startMinuteOfDay
                document.dayPlans[p].blocks[b].resolvedEndMinuteOfDay = c.endMinuteOfDay
                document.dayPlans[p].blocks[b].timing = .absolute(startMinuteOfDay: c.startMinuteOfDay, requestedEndMinuteOfDay: c.endMinuteOfDay)
                if let title = c.title { document.dayPlans[p].blocks[b].title = title }
                document.dayPlans[p].blocks[b].note = c.note
                if let tasks = c.tasks {
                    let previous = document.dayPlans[p].blocks[b].tasks
                    document.dayPlans[p].blocks[b].tasks = tasks.map { definition in
                        var task = previous.first { $0.id == definition.id } ?? TaskItem(id: definition.id, title: definition.title)
                        task.title = definition.title; task.order = definition.order; task.sourceTaskID = definition.sourceTaskID
                        return task
                    }
                }
            }
        }
    }
    private func store(_ document: SamoyedDocument, db: Database) throws {
        try db.execute(sql: "INSERT INTO documents VALUES(?,?) ON CONFLICT(partition) DO UPDATE SET body=excluded.body", arguments: [partition, try JSONEncoder().encode(document)])
    }
    private func applyRemote(_ entity: NestRemoteEntity, to document: inout SamoyedDocument, db: Database) throws {
        let known = try Int.fetchOne(db, sql: "SELECT revision FROM remote_entities WHERE partition=? AND kind=? AND entityID=?", arguments: [partition, entity.kind, entity.id]) ?? 0
        guard entity.revision >= known else { return }
        let data = try JSONEncoder().encode(entity.body)
        try db.execute(sql: "INSERT INTO remote_entities VALUES(?,?,?,?,?,?) ON CONFLICT(partition,kind,entityID) DO UPDATE SET revision=excluded.revision,body=excluded.body,deleted=excluded.deleted", arguments: [partition, entity.kind, entity.id, entity.revision, data, entity.deleted])
        let pending = try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM outbox WHERE partition=? AND kind=? AND entityID=?)", arguments: [partition, entity.kind, entity.id]) ?? false
        guard !pending else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: text) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: text) else { throw CocoaError(.coderInvalidValue) }
            return date
        }
        switch entity.kind {
        case "note":
            var note = try decoder.decode(TimelineNote.self, from: data)
            note.revision = entity.revision
            if entity.deleted { note.deletedAt = note.deletedAt ?? .now }
            document.timelineNotes.removeAll { $0.id == note.id }; document.timelineNotes.append(note)
        case "routine":
            let routine = try decoder.decode(SavedDayTemplate.self, from: data)
            document.savedTemplates.removeAll { $0.id == routine.id }
            if !entity.deleted { document.savedTemplates.append(routine) }
        case "plan", "legacyPlan", "offlinePlan":
            var plan = try decoder.decode(DayPlan.self, from: data); plan.revision = entity.revision
            // An executed cached snapshot keeps its original instance identities, even
            // when the cloud generated another plan while this device was disconnected.
            if let current = document.dayPlans.first(where: { $0.date == plan.date && $0.id != plan.id }) {
                if current.source == "offline", try hasExecution(current.id, db: db) { return }
                if entity.kind == "offlinePlan", !(try hasExecution(plan.id, db: db)) { return }
            }
            document.dayPlans.removeAll { $0.id == plan.id || $0.date == plan.date }
            if !entity.deleted { document.dayPlans.append(plan) }
        case "weekdayRule":
            let rule = try decoder.decode(WeekdayTemplateRule.self, from: data)
            document.weekdayRules.removeAll { $0.weekday == rule.weekday }
            if !entity.deleted { document.weekdayRules.append(rule) }
        case "dateException":
            struct Exception: Decodable { var date: LocalDay; var savedTemplateID: UUID? }
            let value = try decoder.decode(Exception.self, from: data)
            document.overrides.removeAll { $0.date == value.date }
            document.daySelections.removeAll { $0.date == value.date }
            if !entity.deleted {
                if let id = value.savedTemplateID { document.overrides.append(.init(date: value.date, savedTemplateID: id)) }
                document.daySelections.append(.init(date: value.date, selectedTemplateID: value.savedTemplateID, source: value.savedTemplateID == nil ? .noTemplate : .pickedTemplate))
            }
        case "execution":
            struct State: Decodable { var planID: UUID; var blockInstanceID: UUID; var taskInstanceID: UUID; var isCompleted: Bool; var occurredAt: Date }
            let state = try decoder.decode(State.self, from: data)
            if let p = document.dayPlans.firstIndex(where: { $0.id == state.planID }),
               let b = document.dayPlans[p].blocks.firstIndex(where: { $0.id == state.blockInstanceID }),
               let t = document.dayPlans[p].blocks[b].tasks.firstIndex(where: { $0.id == state.taskInstanceID }) {
                document.dayPlans[p].blocks[b].tasks[t].isCompleted = state.isCompleted
                document.dayPlans[p].blocks[b].tasks[t].completedAt = state.isCompleted ? state.occurredAt : nil
            }
        default: break // Retain unrecognized entities in remote_entities for a later client upgrade.
        }
    }
}

/// One sync at a time. A crash after push but before ACK safely retries stable operation IDs.
actor NestSyncEngine {
    private let database: NestLocalDatabase
    private let transport: any NestSyncTransport
    private var running = false
    init(database: NestLocalDatabase, transport: any NestSyncTransport) {
        self.database = database; self.transport = transport
    }
    func sync() async throws {
        guard !running else { return }
        running = true; defer { running = false }
        guard var cursor = try database.cursor() else { throw CocoaError(.coderValueNotFound) }
        while true {
            let pending = try database.pendingOperations()
            if pending.isEmpty { break }
            let commands = try pending.prefix(100).map(NestSyncCommand.init)
            let results = try await transport.push(commands)
            guard Set(results.map(\.operationID)) == Set(commands.map(\.operationID)) else { throw CocoaError(.coderInvalidValue) }
            try database.acknowledge(results)
            if !results.contains(where: { $0.status == "accepted" || $0.status == "rejected" }) { break }
        }
        while true {
            let page = try await transport.pull(cursor: cursor)
            try database.apply(page)
            cursor = page.cursor
            if !page.hasMore { break }
        }
    }
}

struct NestNoteConflict: Identifiable, Equatable, Sendable {
    var id: String
    var local: TimelineNote
    var remote: TimelineNote?
    var remoteDeleted: Bool
}

enum NestNoteConflictChoice: Sendable { case keepLocal, keepRemote }

extension NestLocalDatabase {
    func noteConflicts() throws -> [NestNoteConflict] {
        try queue.read { db in
            let document = try readDocument(db)
            let rows = try Row.fetchAll(db, sql: "SELECT c.operationID,c.remote,o.entityID FROM conflicts c JOIN outbox o ON o.partition=c.partition AND o.operationID=c.operationID WHERE c.partition=? AND o.kind='note'", arguments: [partition])
            return try rows.compactMap { row in
                let entityID: String = row["entityID"]
                guard let local = document.timelineNotes.first(where: { $0.id.uuidString.lowercased() == entityID }) else { return nil }
                let data: Data = row["remote"]
                let remote = try JSONDecoder().decode(NestRemoteEntity?.self, from: data)
                return .init(id: row["operationID"], local: local, remote: try remote.map { try Self.decodeNote($0.body) }, remoteDeleted: remote?.deleted ?? false)
            }
        }
    }

    /// Resolve against the newest pulled remote revision; archive both versions first.
    /// Keeping a note deleted remotely creates a new ID, never resurrects the tombstone.
    func resolveNoteConflict(operationID: String, choice: NestNoteConflictChoice) throws {
        try queue.write { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT c.remote,o.entityID FROM conflicts c JOIN outbox o ON o.partition=c.partition AND o.operationID=c.operationID WHERE c.partition=? AND c.operationID=? AND o.kind='note'", arguments: [partition, operationID]) else { throw CocoaError(.coderValueNotFound) }
            let entityID: String = row["entityID"]
            var document = try readDocument(db)
            guard let local = document.timelineNotes.first(where: { $0.id.uuidString.lowercased() == entityID }) else { throw CocoaError(.coderValueNotFound) }
            let originalRemote: Data = row["remote"]
            var remote = try JSONDecoder().decode(NestRemoteEntity?.self, from: originalRemote)
            if let newest = try Row.fetchOne(db, sql: "SELECT revision,body,deleted FROM remote_entities WHERE partition=? AND kind='note' AND entityID=?", arguments: [partition, entityID]) {
                let revision: Int = newest["revision"]
                if revision >= (remote?.revision ?? 0) {
                    let body: Data = newest["body"]
                    remote = .init(kind: "note", id: entityID, revision: revision, deleted: newest["deleted"], body: try JSONDecoder().decode(NestJSON.self, from: body))
                }
            }
            struct Archive: Encodable { var partition: String; var local: TimelineNote; var remote: NestRemoteEntity? }
            try db.execute(sql: "INSERT INTO migration_archive VALUES(?,?,?)", arguments: ["conflict-\(UUID().uuidString)", try JSONEncoder().encode(Archive(partition: partition, local: local, remote: remote)), Date().timeIntervalSince1970])
            try db.execute(sql: "DELETE FROM conflicts WHERE partition=? AND operationID IN(SELECT operationID FROM outbox WHERE partition=? AND kind='note' AND entityID=?)", arguments: [partition, partition, entityID])
            try db.execute(sql: "DELETE FROM outbox WHERE partition=? AND kind='note' AND entityID=?", arguments: [partition, entityID])
            if let remote { try applyRemote(remote, to: &document, db: db) }
            if choice == .keepLocal && !(remote?.deleted == true && local.deletedAt != nil) {
                var note = local
                if remote?.deleted == true {
                    note.id = UUID()
                    note.createdAt = .now
                    note.deletedAt = nil
                }
                note.revision = remote?.deleted == true ? 0 : (remote?.revision ?? 0)
                note.updatedAt = .now
                document.timelineNotes.removeAll { $0.id == note.id }
                document.timelineNotes.append(note)
                let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
                try db.execute(sql: "INSERT INTO outbox(partition,operationID,kind,entityID,expectedRevision,payload,deleted) VALUES (?,?,?,?,?,?,?)", arguments: [partition, UUID().uuidString.lowercased(), "note", note.id.uuidString.lowercased(), note.revision, try encoder.encode(note), note.deletedAt != nil])
            } else if remote == nil {
                // A rejected creation has no cloud counterpart. Keep it in the archive, not the timeline.
                document.timelineNotes.removeAll { $0.id == local.id }
            }
            try store(document, db: db)
        }
    }

    private static func decodeNote(_ body: NestJSON) throws -> TimelineNote {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: text) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: text) else { throw CocoaError(.coderInvalidValue) }
            return date
        }
        return try decoder.decode(TimelineNote.self, from: JSONEncoder().encode(body))
    }
}


struct NestDomainConflict: Identifiable, Sendable {
    var id: String
    var kind: String
    var localSummary: String
    var remoteSummary: String
    var canKeepLocal: Bool
}

extension NestLocalDatabase {
    func domainConflicts() throws -> [NestDomainConflict] {
        try queue.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT c.operationID,c.reason,c.remote,o.kind,o.entityID FROM conflicts c JOIN outbox o ON o.partition=c.partition AND o.operationID=c.operationID WHERE c.partition=? AND o.kind!='note' ORDER BY o.sequence", arguments: [partition])
            return try rows.map { row in
                let kind: String = row["kind"], id: String = row["entityID"], reason: String = row["reason"]
                let payload = try Data.fetchOne(db, sql: "SELECT payload FROM outbox WHERE partition=? AND kind=? AND entityID=? ORDER BY sequence DESC LIMIT 1", arguments: [partition, kind, id])!
                let local = try JSONDecoder().decode(NestJSON.self, from: payload)
                let data: Data = row["remote"]
                let remote = try JSONDecoder().decode(NestRemoteEntity?.self, from: data)
                return .init(id: row["operationID"], kind: kind, localSummary: Self.conflictSummary(local), remoteSummary: remote?.deleted == true ? "已在 Nest 删除" : remote.map { Self.conflictSummary($0.body) } ?? "未保存到 Nest，请重新检查这项修改。", canKeepLocal: kind != "legacyPlan" && remote != nil && remote?.deleted != true && ["revision_conflict", "stale_plan"].contains(reason))
            }
        }
    }

    /// Explicit user choice rebases only this object's latest desired edit. All rejected
    /// commands and their remote counterpart are archived before removing the queue entries.
    func resolveDomainConflict(operationID: String, keepLocal: Bool) throws {
        try queue.write { db in
            guard let conflict = try Row.fetchOne(db, sql: "SELECT c.remote,c.reason,o.kind,o.entityID FROM conflicts c JOIN outbox o ON o.partition=c.partition AND o.operationID=c.operationID WHERE c.partition=? AND c.operationID=? AND o.kind!='note'", arguments: [partition, operationID]) else { throw CocoaError(.coderValueNotFound) }
            let kind: String = conflict["kind"], id: String = conflict["entityID"], reason: String = conflict["reason"], remoteData: Data = conflict["remote"]
            let originalRemote = try JSONDecoder().decode(NestRemoteEntity?.self, from: remoteData)
            let queued = try Row.fetchAll(db, sql: "SELECT operationID,payload,deleted FROM outbox WHERE partition=? AND kind=? AND entityID=? ORDER BY sequence", arguments: [partition, kind, id])
            guard let latest = queued.last else { throw CocoaError(.coderValueNotFound) }
            var payload: Data = latest["payload"]
            let deleted: Bool = latest["deleted"]
            var document = try readDocument(db)
            if let originalRemote { try applyRemote(originalRemote, to: &document, db: db) }
            let ownRemote = try Row.fetchOne(db, sql: "SELECT revision,deleted FROM remote_entities WHERE partition=? AND kind=? AND entityID=?", arguments: [partition, kind, id])
            let remoteDeleted: Bool = ownRemote?["deleted"] ?? originalRemote?.deleted ?? false
            let revision: Int = ownRemote?["revision"] ?? (originalRemote?.kind == kind ? originalRemote?.revision ?? 0 : 0)
            if keepLocal {
                guard kind != "legacyPlan", !remoteDeleted, originalRemote != nil, ["revision_conflict", "stale_plan"].contains(reason) else { throw CocoaError(.coderInvalidValue) }
                if kind == "dayCorrection" {
                    guard case var .object(value) = try JSONDecoder().decode(NestJSON.self, from: payload), case let .string(planID)? = value["planID"], case let .string(blockID)? = value["blockInstanceID"],
                          let row = try Row.fetchOne(db, sql: "SELECT revision,body FROM remote_entities WHERE partition=? AND kind IN ('plan','legacyPlan','offlinePlan') AND entityID=? ORDER BY revision DESC LIMIT 1", arguments: [partition, planID.lowercased()]) else { throw CocoaError(.coderValueNotFound) }
                    let data: Data = row["body"]
                    guard case let .object(plan) = try JSONDecoder().decode(NestJSON.self, from: data), case let .array(blocks)? = plan["blocks"], blocks.contains(where: { if case let .object(b) = $0, case let .string(i)? = b["id"] { return i.lowercased() == blockID.lowercased() }; return false }) else { throw CocoaError(.coderValueNotFound) }
                    let planRevision: Int = row["revision"]; value["planRevision"] = .number(Double(planRevision)); payload = try JSONEncoder().encode(NestJSON.object(value))
                }
            }
            struct ArchivedCommand: Encodable { var operationID: String; var payload: Data; var deleted: Bool }
            struct Archive: Encodable { var kind: String; var entityID: String; var commands: [ArchivedCommand]; var remote: Data }
            let archive = Archive(kind: kind, entityID: id, commands: queued.map { .init(operationID: $0["operationID"], payload: $0["payload"], deleted: $0["deleted"]) }, remote: remoteData)
            try db.execute(sql: "INSERT INTO migration_archive VALUES(?,?,?)", arguments: ["conflict-\(UUID().uuidString)", try JSONEncoder().encode(archive), Date().timeIntervalSince1970])
            try db.execute(sql: "DELETE FROM conflicts WHERE partition=? AND operationID IN(SELECT operationID FROM outbox WHERE partition=? AND kind=? AND entityID=?)", arguments: [partition, partition, kind, id])
            try db.execute(sql: "DELETE FROM outbox WHERE partition=? AND kind=? AND entityID=?", arguments: [partition, kind, id])
            let replacementID = UUID().uuidString.lowercased()
            if keepLocal {
                // Keep this correction ahead of executions that refer to its new task IDs.
                let oldSequence = try Int.fetchOne(db, sql: "SELECT MIN(sequence) FROM outbox") ?? 1
                try db.execute(sql: "INSERT INTO outbox(sequence,partition,operationID,kind,entityID,expectedRevision,payload,deleted) VALUES(?,?,?,?,?,?,?,?)", arguments: [min(oldSequence - 1, 0), partition, replacementID, kind, id, revision, payload, deleted])
            } else {
                switch kind {
                case "routine": document.savedTemplates.removeAll { $0.id.uuidString.lowercased() == id }
                case "weekdayRule": document.weekdayRules.removeAll { String($0.weekday.rawValue) == id }
                case "dateException":
                    let match: (LocalDay) -> Bool = { String(format: "%04d-%02d-%02d", $0.year, $0.month, $0.day) == id }
                    document.overrides.removeAll { match($0.date) }; document.daySelections.removeAll { match($0.date) }
                default: break
                }
            }
            if kind == "dayCorrection" {
                let previousIDs = Set(queued.map { $0["operationID"] as String })
                let dependencies = try Row.fetchAll(db, sql: "SELECT operationID,payload FROM outbox WHERE partition=? AND kind='execution'", arguments: [partition])
                for dependency in dependencies {
                    let operationID: String = dependency["operationID"], bytes: Data = dependency["payload"]
                    guard case var .object(state) = try JSONDecoder().decode(NestJSON.self, from: bytes), case let .string(link)? = state["correctionOperationID"], previousIDs.contains(link) else { continue }
                    if keepLocal, case let .object(correction) = try JSONDecoder().decode(NestJSON.self, from: payload) {
                        state["correctionOperationID"] = .string(replacementID); state["planRevision"] = correction["planRevision"]
                        // A changed command receives a fresh idempotency ID, even if a
                        // previous network attempt returned unknown_correction.
                        try db.execute(sql: "DELETE FROM conflicts WHERE partition=? AND operationID=?", arguments: [partition, operationID])
                        try db.execute(sql: "UPDATE outbox SET operationID=?,payload=?,status='pending' WHERE partition=? AND operationID=?", arguments: [UUID().uuidString.lowercased(), try JSONEncoder().encode(NestJSON.object(state)), partition, operationID])
                    } else {
                        try db.execute(sql: "UPDATE outbox SET status='conflict' WHERE partition=? AND operationID=?", arguments: [partition, operationID])
                        try db.execute(sql: "INSERT OR REPLACE INTO conflicts(partition,operationID,local,remote,reason) VALUES(?,?,?,?,?)", arguments: [partition, operationID, bytes, Data("null".utf8), "correction_discarded"])
                    }
                }
            }
            // Reproject durable remote bases and the remaining optimistic operations.
            let rows = try Row.fetchAll(db, sql: "SELECT kind,entityID,revision,body,deleted FROM remote_entities WHERE partition=? ORDER BY CASE WHEN kind IN('plan','legacyPlan') THEN 0 WHEN kind='execution' THEN 2 ELSE 1 END", arguments: [partition])
            for row in rows {
                let data: Data = row["body"]
                try applyRemote(.init(kind: row["kind"], id: row["entityID"], revision: row["revision"], deleted: row["deleted"], body: try JSONDecoder().decode(NestJSON.self, from: data)), to: &document, db: db)
            }
            try projectCorrections(to: &document, db: db); try projectExecutions(to: &document, db: db)
            try store(document, db: db)
        }
    }

    private static func conflictSummary(_ body: NestJSON) -> String {
        guard case let .object(v) = body else { return "这项修改没有可显示的内容。" }
        var lines: [String] = []
        if case let .string(title)? = v["title"] { lines.append(title) }
        if case let .bool(completed)? = v["isCompleted"] { lines.append(completed ? "任务已完成" : "任务未完成") }
        if case let .string(at)? = v["occurredAt"] { lines.append(at) }
        if case let .number(day)? = v["weekday"] { lines.append("星期规则：\(Int(day))") }
        if case let .object(d)? = v["date"], case let .number(y)? = d["year"], case let .number(m)? = d["month"], case let .number(day)? = d["day"] { lines.append("\(Int(y))-\(Int(m))-\(Int(day))") }
        if case let .array(blocks)? = v["blocks"] { for block in blocks { if case let .object(b) = block, case let .string(title)? = b["title"] { lines.append(title) } } }
        if case let .number(start)? = v["startMinuteOfDay"], case let .number(end)? = v["endMinuteOfDay"] { lines.append(String(format: "%02d:%02d–%02d:%02d", Int(start)/60, Int(start)%60, Int(end)/60, Int(end)%60)) }
        if case .null? = v["savedTemplateID"] { lines.append("不选择 Routine") }
        return lines.isEmpty ? "日程选择已修改" : lines.joined(separator: "\n")
    }
}

private struct NestTaskDefinition: Codable, Equatable {
    var id: UUID; var sourceTaskID: UUID?; var title: String; var order: Int
    init(_ task: TaskItem) { id = task.id; sourceTaskID = task.sourceTaskID; title = task.title; order = task.order }
}
