import Foundation

public enum FeedbackTarget: Equatable, Codable, Sendable {
    case block(blockID: UUID)
    case transition(fromBlockID: UUID?, toBlockID: UUID?)
    case wholeDay
}

public enum FeedbackSentiment: String, CaseIterable, Equatable, Codable, Sendable {
    case good
    case tooRushed
    case tooLoose
    case tired
    case uncomfortable
}

public enum FeedbackSource: String, Equatable, Codable, Sendable {
    case now
    case today
    case blockDetails
}

public enum FeedbackSyncState: String, Equatable, Codable, Sendable {
    case localOnly
    case pending
    case synced
}

public struct FeedbackEvent: Identifiable, Equatable, Codable, Sendable {
    public var id: UUID
    public var target: FeedbackTarget
    public var localDay: LocalDay
    public var observedAt: Date
    public var sentiment: FeedbackSentiment?
    public var note: String?
    public var source: FeedbackSource
    public var syncState: FeedbackSyncState

    public init(
        id: UUID = UUID(),
        target: FeedbackTarget,
        localDay: LocalDay,
        observedAt: Date = .now,
        sentiment: FeedbackSentiment? = nil,
        note: String? = nil,
        source: FeedbackSource,
        syncState: FeedbackSyncState = .localOnly
    ) {
        self.id = id
        self.target = target
        self.localDay = localDay
        self.observedAt = observedAt
        self.sentiment = sentiment
        self.note = note
        self.source = source
        self.syncState = syncState
    }
}

enum FeedbackServiceError: Error, Equatable, Sendable {
    case emptyFeedback
}

extension FeedbackServiceError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .emptyFeedback:
            return "Choose how it felt or add a note."
        }
    }
}

enum FeedbackSyncAvailability: Equatable, Sendable {
    case none
    case configuredOffline
}
