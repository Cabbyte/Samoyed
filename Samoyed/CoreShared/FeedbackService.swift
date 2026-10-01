import Foundation

struct FeedbackService {
    private let repository: SamoyedDocumentRepository
    private let syncAvailability: FeedbackSyncAvailability

    init(
        repository: SamoyedDocumentRepository = .appLive,
        syncAvailability: FeedbackSyncAvailability = .none
    ) {
        self.repository = repository
        self.syncAvailability = syncAvailability
    }

    @discardableResult
    func save(_ event: FeedbackEvent) throws -> FeedbackEvent {
        let trimmedNote = event.note?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard event.sentiment != nil || !(trimmedNote ?? "").isEmpty else {
            throw FeedbackServiceError.emptyFeedback
        }

        return try repository.mutate { document in
            if let existing = document.feedbackEvents.first(where: { $0.id == event.id }) {
                return existing
            }

            var saved = event
            saved.note = (trimmedNote ?? "").isEmpty ? nil : trimmedNote
            saved.syncState = switch syncAvailability {
            case .none: .localOnly
            case .configuredOffline: .pending
            }
            document.feedbackEvents.append(saved)
            return saved
        }.value
    }
}
