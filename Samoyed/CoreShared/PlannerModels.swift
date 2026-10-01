import Foundation

public enum PlannerConnectionState: String, Equatable, Codable, Sendable {
    case disconnected
    case connected
    case unavailable
    case needsAttention
}

public struct PlannerSettings: Equatable, Codable, Sendable {
    public var connectionState: PlannerConnectionState
    public var planningTime: DateComponents?
    public var externalURL: URL?

    public init(
        connectionState: PlannerConnectionState = .disconnected,
        planningTime: DateComponents? = nil,
        externalURL: URL? = nil
    ) {
        self.connectionState = connectionState
        self.planningTime = planningTime
        self.externalURL = externalURL
    }
}

protocol PlannerClient: Sendable {
    func connectionState() async -> PlannerConnectionState
    func externalURL() async -> URL?
    func updatePlanningTime(_ planningTime: DateComponents?) async throws
    func fetchSuggestions() async throws -> [Suggestion]
}

enum PlannerClientError: Error, Equatable, Sendable {
    case unavailable
}

extension PlannerClientError: LocalizedError {
    var errorDescription: String? {
        "Planner service is not available. Your approved routines still work locally."
    }
}

struct UnavailablePlannerClient: PlannerClient {
    let reportedState: PlannerConnectionState

    init(reportedState: PlannerConnectionState = .disconnected) {
        self.reportedState = reportedState
    }

    func connectionState() async -> PlannerConnectionState {
        reportedState
    }

    func externalURL() async -> URL? {
        nil
    }

    func updatePlanningTime(_ planningTime: DateComponents?) async throws {
        _ = planningTime
        throw PlannerClientError.unavailable
    }

    func fetchSuggestions() async throws -> [Suggestion] {
        throw PlannerClientError.unavailable
    }
}
