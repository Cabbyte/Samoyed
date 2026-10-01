import Foundation

/// A point on the timeline. Independent of plan duration and checklist state.
public struct TimelineNote: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var text: String
    public var occurredAt: Date
    public var timeZoneID: String
    public var blockInstanceID: UUID?
    public var createdAt: Date
    public var updatedAt: Date
    public var revision: Int
    public var source: String
    public var deletedAt: Date?

    public init(id: UUID = UUID(), text: String, occurredAt: Date = .now,
                timeZoneID: String = TimeZone.current.identifier, blockInstanceID: UUID? = nil,
                createdAt: Date = .now, updatedAt: Date = .now, revision: Int = 0,
                source: String = "ios", deletedAt: Date? = nil) {
        self.id = id; self.text = text; self.occurredAt = occurredAt
        self.timeZoneID = timeZoneID; self.blockInstanceID = blockInstanceID
        self.createdAt = createdAt; self.updatedAt = updatedAt; self.revision = revision
        self.source = source; self.deletedAt = deletedAt
    }
}

public extension SamoyedDocument {
    func timelineNotes(on day: LocalDay, timeZone: TimeZone = .current) -> [TimelineNote] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return timelineNotes.filter {
            let parts = calendar.dateComponents([.year, .month, .day], from: $0.occurredAt)
            return $0.deletedAt == nil && parts.year == day.year && parts.month == day.month && parts.day == day.day
        }.sorted { ($0.occurredAt, $0.id.uuidString) < ($1.occurredAt, $1.id.uuidString) }
    }
}

// The wire spelling remains `note` for existing routine configuration files.
public extension TimeBlock {
    var guidance: String? { get { note } set { note = newValue } }
}
public extension BlockTemplate {
    var guidance: String? { get { note } set { note = newValue } }
}
