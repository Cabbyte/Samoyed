import Foundation

struct SuggestionService {
    private let repository: SamoyedDocumentRepository
    private let inlineDecoder: SamoyedInlineSuggestionDecoder

    init(
        repository: SamoyedDocumentRepository = .appLive,
        inlineDecoder: SamoyedInlineSuggestionDecoder = SamoyedInlineSuggestionDecoder()
    ) {
        self.repository = repository
        self.inlineDecoder = inlineDecoder
    }

    @discardableResult
    func importSuggestion(version: Int, payload: String) throws -> Suggestion {
        let suggestion = try inlineDecoder.decode(version: version, payload: payload)
        return try importSuggestion(suggestion)
    }

    @discardableResult
    func importSuggestion(_ suggestion: Suggestion) throws -> Suggestion {
        try Self.validate(suggestion)
        return try repository.mutate { document in
            if let existing = document.suggestions.first(where: { $0.id == suggestion.id }) {
                return existing
            }
            document.suggestions.append(suggestion)
            return suggestion
        }.value
    }

    @discardableResult
    func reject(_ suggestionID: UUID, at rejectedAt: Date = .now) throws -> Suggestion {
        try repository.mutate { document in
            guard let index = document.suggestions.firstIndex(where: { $0.id == suggestionID }) else {
                throw SuggestionServiceError.missingSuggestion(suggestionID)
            }
            if document.suggestions[index].lifecycleState == .rejected {
                return document.suggestions[index]
            }
            guard document.suggestions[index].lifecycleState == .pending else {
                throw SuggestionServiceError.suggestionNotPending(document.suggestions[index].lifecycleState)
            }
            document.suggestions[index].lifecycleState = .rejected
            document.suggestions[index].updatedAt = rejectedAt
            return document.suggestions[index]
        }.value
    }

    @discardableResult
    func accept(
        _ suggestionID: UUID,
        today: LocalDay,
        allowReplacingExecutionState: Bool = false,
        at acceptedAt: Date = .now
    ) throws -> Suggestion {
        try repository.mutate { document in
            guard let index = document.suggestions.firstIndex(where: { $0.id == suggestionID }) else {
                throw SuggestionServiceError.missingSuggestion(suggestionID)
            }
            let suggestion = document.suggestions[index]
            if suggestion.lifecycleState == .accepted {
                return suggestion
            }
            guard suggestion.lifecycleState == .pending else {
                throw SuggestionServiceError.suggestionNotPending(suggestion.lifecycleState)
            }

            var candidate = document
            switch suggestion.kind {
            case .dailyPlan:
                guard let payload = suggestion.dailyPlanPayload else {
                    throw SuggestionServiceError.invalidSuggestion
                }
                if let current = candidate.dayPlan(for: payload.targetDate),
                   current.hasUserEdits || current.containsCompletedTasks,
                   !allowReplacingExecutionState {
                    throw SuggestionServiceError.requiresExecutionStateConfirmation(payload.targetDate)
                }
                let resolvedPlan = try DayPlanEngine.resolved(payload.proposedDayPlan)
                guard resolvedPlan.date == payload.targetDate else {
                    throw SuggestionServiceError.targetDateMismatch
                }
                candidate.dayPlans.removeAll { $0.date == payload.targetDate }
                candidate.dayPlans.append(resolvedPlan)
                candidate.dayPlans.sort { $0.date < $1.date }

            case .routineImprovement:
                guard let payload = suggestion.routineImprovementPayload,
                      let templateIndex = candidate.savedTemplates.firstIndex(where: { $0.id == payload.routineID })
                else {
                    throw SuggestionServiceError.invalidSuggestion
                }
                let current = candidate.savedTemplates[templateIndex]
                let provenance = RoutineVersionProvenance(
                    source: .plannerSuggestion,
                    suggestionID: suggestion.id,
                    feedbackEventIDs: suggestion.evidence?.feedbackEventIDs ?? [],
                    recordedAt: acceptedAt
                )
                if !candidate.routineRevisionSnapshots.contains(where: { $0.versionID == current.versionID }) {
                    candidate.routineRevisionSnapshots.append(
                        RoutineRevisionSnapshot(
                            id: current.versionID,
                            routineID: current.id,
                            logicalRoutineID: current.logicalRoutineID,
                            revision: current.revision,
                            versionID: current.versionID,
                            parentVersionID: current.parentVersionID,
                            title: current.title,
                            blocks: current.blocks,
                            createdAt: current.updatedAt,
                            provenance: current.provenance
                        )
                    )
                }
                let newVersionID = UUID()
                var improved = current
                improved.title = payload.proposedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                improved.blocks = payload.proposedBlocks
                improved.updatedAt = acceptedAt
                improved.revision = current.revision + 1
                improved.parentVersionID = current.versionID
                improved.versionID = newVersionID
                improved.provenance = provenance
                _ = try TemplateEngine.previewDayPlan(from: improved)
                candidate.savedTemplates[templateIndex] = improved
            }

            candidate.suggestions[index].lifecycleState = .accepted
            candidate.suggestions[index].updatedAt = acceptedAt
            // Publish the fully validated candidate in one repository transaction.
            document = candidate
            _ = today // Routine changes intentionally do not rematerialize Today.
            return document.suggestions[index]
        }.value
    }

    static func validate(_ suggestion: Suggestion) throws {
        guard suggestion.schemaVersion == 1 else {
            throw SuggestionServiceError.unsupportedVersion(suggestion.schemaVersion)
        }
        guard suggestion.lifecycleState == .pending else {
            throw SuggestionServiceError.invalidSuggestion
        }
        guard !suggestion.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SuggestionServiceError.invalidSuggestion
        }
        switch suggestion.kind {
        case .dailyPlan:
            guard let payload = suggestion.dailyPlanPayload,
                  suggestion.routineImprovementPayload == nil,
                  payload.proposedDayPlan.date == payload.targetDate
            else {
                throw SuggestionServiceError.invalidSuggestion
            }
            _ = try DayPlanEngine.resolved(payload.proposedDayPlan)
        case .routineImprovement:
            guard let payload = suggestion.routineImprovementPayload,
                  suggestion.dailyPlanPayload == nil,
                  !payload.proposedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !payload.proposedBlocks.isEmpty
            else {
                throw SuggestionServiceError.invalidSuggestion
            }
            let candidate = SavedDayTemplate(
                id: payload.routineID,
                title: payload.proposedTitle,
                blocks: payload.proposedBlocks
            )
            _ = try TemplateEngine.previewDayPlan(from: candidate)
        }
    }
}
