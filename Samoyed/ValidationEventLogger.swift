import Foundation

actor ValidationEventLogger {
    static let shared = ValidationEventLogger(enabled: ValidationRuntime.isEnabled)

    private let enabled: Bool
    private let participantID: UUID
    private let sessionID = UUID()
    private let fileURL: URL
    private let encoder: JSONEncoder

    init(
        enabled: Bool,
        participantID: UUID? = nil,
        fileURL: URL? = nil
    ) {
        self.enabled = enabled
        self.participantID = participantID
            ?? (enabled ? ValidationRuntime.participantID() : UUID())
        self.fileURL = fileURL ?? ValidationRuntime.defaultLogURL()
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
    }

    func record(
        _ name: ValidationEventName,
        outcome: String? = nil,
        variant: String? = nil,
        durationMilliseconds: Int? = nil,
        at date: Date = .now
    ) {
        guard enabled else { return }
        let event = ValidationEvent(
            participantID: participantID,
            sessionID: sessionID,
            occurredAt: date,
            name: name,
            outcome: outcome,
            variant: variant,
            durationMilliseconds: durationMilliseconds
        )

        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let line = try encoder.encode(event) + Data([0x0A])
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let handle = try FileHandle(forWritingTo: fileURL)
                try handle.seekToEnd()
                try handle.write(contentsOf: line)
                try handle.close()
            } else {
                try line.write(to: fileURL, options: .atomic)
            }
        } catch {
            // Validation telemetry must never block or alter the product flow.
        }
    }

    func exportURL() -> URL? {
        guard enabled, FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        return fileURL
    }

    func clear() {
        guard enabled else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }
}

enum ValidationRuntime {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["SAMOYED_VALIDATION"] == "1"
    }

    static func participantID(defaults: UserDefaults = .standard) -> UUID {
        let key = "Samoyed.Validation.ParticipantID"
        if let stored = defaults.string(forKey: key), let id = UUID(uuidString: stored) {
            return id
        }
        let id = UUID()
        defaults.set(id.uuidString, forKey: key)
        return id
    }

    static func defaultLogURL(fileManager: FileManager = .default) -> URL {
        let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return root
            .appending(path: "SamoyedValidation", directoryHint: .isDirectory)
            .appending(path: "validation-events.jsonl")
    }
}
