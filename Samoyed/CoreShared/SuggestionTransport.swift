import Foundation

enum SuggestionTransportError: Error, Equatable, Sendable {
    case unsupportedVersion(Int)
    case emptyPayload
    case invalidBase64URL
    case payloadTooLarge(maximumBytes: Int)
    case invalidUTF8
    case invalidJSON
    case invalidURL
    case embeddedCredentials
    case insecureTransport
    case invalidResponse
    case unsuccessfulStatus(Int)
}

extension SuggestionTransportError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case let .unsupportedVersion(version):
            return "Suggestion link version \(version) is not supported."
        case .emptyPayload:
            return "The suggestion link does not contain a payload."
        case .invalidBase64URL:
            return "The suggestion payload is not valid Base64URL data."
        case let .payloadTooLarge(maximumBytes):
            return "The suggestion payload is larger than \(maximumBytes / 1024) KB."
        case .invalidUTF8:
            return "The suggestion payload must be UTF-8 JSON."
        case .invalidJSON:
            return "The suggestion payload is not valid JSON."
        case .invalidURL:
            return "The suggestion URL must include a valid host."
        case .embeddedCredentials:
            return "Suggestion URLs cannot contain embedded credentials."
        case .insecureTransport:
            return "Suggestion imports require HTTPS."
        case .invalidResponse:
            return "The suggestion server returned an invalid response."
        case let .unsuccessfulStatus(status):
            return "The suggestion server returned HTTP status \(status)."
        }
    }
}

struct SamoyedInlineSuggestionDecoder: Sendable {
    static let supportedVersion = 1
    static let defaultMaximumBytes = 32 * 1024

    private let maximumBytes: Int

    init(maximumBytes: Int = defaultMaximumBytes) {
        precondition(maximumBytes > 0)
        self.maximumBytes = maximumBytes
    }

    func decode(version: Int, payload: String) throws -> Suggestion {
        guard version == Self.supportedVersion else {
            throw SuggestionTransportError.unsupportedVersion(version)
        }
        let data = try decodeBase64URL(payload)
        guard String(data: data, encoding: .utf8) != nil else {
            throw SuggestionTransportError.invalidUTF8
        }
        do {
            return try JSONDecoder().decode(Suggestion.self, from: data)
        } catch {
            throw SuggestionTransportError.invalidJSON
        }
    }

    private func decodeBase64URL(_ payload: String) throws -> Data {
        guard !payload.isEmpty else {
            throw SuggestionTransportError.emptyPayload
        }
        let maximumEncodedCharacters = ((maximumBytes + 2) / 3) * 4
        guard payload.utf8.count <= maximumEncodedCharacters else {
            throw SuggestionTransportError.payloadTooLarge(maximumBytes: maximumBytes)
        }
        guard payload.utf8.allSatisfy(Self.isBase64URLCharacter) else {
            throw SuggestionTransportError.invalidBase64URL
        }

        var base64 = payload
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        switch base64.utf8.count % 4 {
        case 0: break
        case 2: base64.append("==")
        case 3: base64.append("=")
        default: throw SuggestionTransportError.invalidBase64URL
        }
        guard let data = Data(base64Encoded: base64) else {
            throw SuggestionTransportError.invalidBase64URL
        }
        guard data.count <= maximumBytes else {
            throw SuggestionTransportError.payloadTooLarge(maximumBytes: maximumBytes)
        }
        return data
    }

    private static func isBase64URLCharacter(_ byte: UInt8) -> Bool {
        switch byte {
        case 45, 48 ... 57, 65 ... 90, 95, 97 ... 122: true
        default: false
        }
    }
}

struct SamoyedRemoteSuggestionLoader: Sendable {
    static let defaultMaximumBytes = 512 * 1024

    private let maximumBytes: Int
    private let dataLoader: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    init(
        maximumBytes: Int = defaultMaximumBytes,
        dataLoader: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse)
    ) {
        precondition(maximumBytes > 0)
        self.maximumBytes = maximumBytes
        self.dataLoader = dataLoader
    }

    func load(from remoteURL: URL) async throws -> Suggestion {
        try Self.validate(remoteURL)
        var request = URLRequest(
            url: remoteURL,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 15
        )
        request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await dataLoader(request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse, let finalURL = response.url else {
            throw SuggestionTransportError.invalidResponse
        }
        try Self.validate(finalURL)
        guard (200 ..< 300).contains(response.statusCode) else {
            throw SuggestionTransportError.unsuccessfulStatus(response.statusCode)
        }
        guard data.count <= maximumBytes else {
            throw SuggestionTransportError.payloadTooLarge(maximumBytes: maximumBytes)
        }
        guard String(data: data, encoding: .utf8) != nil else {
            throw SuggestionTransportError.invalidUTF8
        }
        do {
            return try JSONDecoder().decode(Suggestion.self, from: data)
        } catch {
            throw SuggestionTransportError.invalidJSON
        }
    }

    static func validate(_ url: URL) throws {
        guard let scheme = url.scheme?.lowercased(), let host = url.host, !host.isEmpty else {
            throw SuggestionTransportError.invalidURL
        }
        guard url.user == nil, url.password == nil else {
            throw SuggestionTransportError.embeddedCredentials
        }
        guard scheme == "https" else {
            throw SuggestionTransportError.insecureTransport
        }
    }
}
