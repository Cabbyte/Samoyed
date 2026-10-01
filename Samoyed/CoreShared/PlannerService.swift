import Foundation

struct PlannerService {
    private let repository: SamoyedDocumentRepository
    private let client: any PlannerClient

    init(
        repository: SamoyedDocumentRepository = .appLive,
        client: any PlannerClient = UnavailablePlannerClient()
    ) {
        self.repository = repository
        self.client = client
    }

    func refreshConnectionState() async throws -> PlannerSettings {
        let state = await client.connectionState()
        let externalURL = await client.externalURL()
        return try repository.mutate { document in
            document.plannerSettings.connectionState = state
            document.plannerSettings.externalURL = externalURL
            return document.plannerSettings
        }.value
    }

    func updatePlanningTime(_ planningTime: DateComponents?) async throws -> PlannerSettings {
        try await client.updatePlanningTime(planningTime)
        return try repository.mutate { document in
            document.plannerSettings.planningTime = planningTime
            return document.plannerSettings
        }.value
    }

    func fetchSuggestions() async throws -> [Suggestion] {
        try await client.fetchSuggestions()
    }
}
