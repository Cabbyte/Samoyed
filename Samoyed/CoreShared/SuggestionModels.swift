import Foundation

public enum SuggestionKind: String, Equatable, Codable, Sendable {
    case dailyPlan
    case routineImprovement
}

public enum SuggestionLifecycleState: String, Equatable, Codable, Sendable {
    case pending
    case accepted
    case rejected
    case expired
}

public struct SuggestionChange: Identifiable, Equatable, Codable, Sendable {
    public var id: UUID
    public var title: String
    public var detail: String?

    public init(id: UUID = UUID(), title: String, detail: String? = nil) {
        self.id = id
        self.title = title
        self.detail = detail
    }
}

public struct SuggestionEvidence: Equatable, Codable, Sendable {
    public var summary: String?
    public var feedbackEventIDs: [UUID]

    public init(summary: String? = nil, feedbackEventIDs: [UUID] = []) {
        self.summary = summary
        self.feedbackEventIDs = feedbackEventIDs
    }
}

public struct DailyPlanSuggestionPayload: Equatable, Codable, Sendable {
    public var targetDate: LocalDay
    public var proposedDayPlan: DayPlan

    public init(targetDate: LocalDay, proposedDayPlan: DayPlan) {
        self.targetDate = targetDate
        self.proposedDayPlan = proposedDayPlan
    }
}

public struct RoutineImprovementPayload: Equatable, Codable, Sendable {
    public var routineID: UUID
    public var proposedTitle: String
    public var proposedBlocks: [BlockTemplate]

    public init(routineID: UUID, proposedTitle: String, proposedBlocks: [BlockTemplate]) {
        self.routineID = routineID
        self.proposedTitle = proposedTitle
        self.proposedBlocks = proposedBlocks
    }
}

public struct Suggestion: Identifiable, Equatable, Codable, Sendable {
    public var schemaVersion: Int
    public var id: UUID
    public var kind: SuggestionKind
    public var lifecycleState: SuggestionLifecycleState
    public var title: String
    public var summary: String?
    public var changes: [SuggestionChange]
    public var evidence: SuggestionEvidence?
    public var dailyPlanPayload: DailyPlanSuggestionPayload?
    public var routineImprovementPayload: RoutineImprovementPayload?
    public var createdAt: Date
    public var updatedAt: Date
    public var expiresAt: Date?

    public init(
        schemaVersion: Int = 1,
        id: UUID = UUID(),
        kind: SuggestionKind,
        lifecycleState: SuggestionLifecycleState = .pending,
        title: String,
        summary: String? = nil,
        changes: [SuggestionChange] = [],
        evidence: SuggestionEvidence? = nil,
        dailyPlanPayload: DailyPlanSuggestionPayload? = nil,
        routineImprovementPayload: RoutineImprovementPayload? = nil,
        createdAt: Date = .now,
        updatedAt: Date? = nil,
        expiresAt: Date? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.kind = kind
        self.lifecycleState = lifecycleState
        self.title = title
        self.summary = summary
        self.changes = changes
        self.evidence = evidence
        self.dailyPlanPayload = dailyPlanPayload
        self.routineImprovementPayload = routineImprovementPayload
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.expiresAt = expiresAt
    }
}

public enum RoutineVersionSource: String, Equatable, Codable, Sendable {
    case imported
    case plannerSuggestion
    case local
}

public struct RoutineVersionProvenance: Equatable, Codable, Sendable {
    public var source: RoutineVersionSource
    public var suggestionID: UUID?
    public var feedbackEventIDs: [UUID]
    public var recordedAt: Date

    public init(
        source: RoutineVersionSource,
        suggestionID: UUID? = nil,
        feedbackEventIDs: [UUID] = [],
        recordedAt: Date = .now
    ) {
        self.source = source
        self.suggestionID = suggestionID
        self.feedbackEventIDs = feedbackEventIDs
        self.recordedAt = recordedAt
    }
}

public struct RoutineRevisionSnapshot: Identifiable, Equatable, Codable, Sendable {
    public var id: UUID
    public var routineID: UUID
    public var logicalRoutineID: UUID
    public var revision: Int
    public var versionID: UUID
    public var parentVersionID: UUID?
    public var title: String
    public var blocks: [BlockTemplate]
    public var createdAt: Date
    public var provenance: RoutineVersionProvenance?

    public init(
        id: UUID = UUID(),
        routineID: UUID,
        logicalRoutineID: UUID,
        revision: Int,
        versionID: UUID,
        parentVersionID: UUID?,
        title: String,
        blocks: [BlockTemplate],
        createdAt: Date,
        provenance: RoutineVersionProvenance?
    ) {
        self.id = id
        self.routineID = routineID
        self.logicalRoutineID = logicalRoutineID
        self.revision = revision
        self.versionID = versionID
        self.parentVersionID = parentVersionID
        self.title = title
        self.blocks = blocks
        self.createdAt = createdAt
        self.provenance = provenance
    }
}

enum SuggestionServiceError: Error, Equatable, Sendable {
    case unsupportedVersion(Int)
    case invalidSuggestion
    case missingSuggestion(UUID)
    case suggestionNotPending(SuggestionLifecycleState)
    case requiresExecutionStateConfirmation(LocalDay)
    case targetDateMismatch
}

extension SuggestionServiceError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case let .unsupportedVersion(version):
            return "Suggestion version \(version) is not supported."
        case .invalidSuggestion:
            return "The suggestion is incomplete or invalid."
        case .missingSuggestion:
            return "The suggestion could not be found."
        case .suggestionNotPending:
            return "This suggestion has already been handled."
        case .requiresExecutionStateConfirmation:
            return "This day already has execution state and cannot be replaced without confirmation."
        case .targetDateMismatch:
            return "The suggested plan does not match its target date."
        }
    }
}
