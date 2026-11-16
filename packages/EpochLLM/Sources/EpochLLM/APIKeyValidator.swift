import Foundation

/// Checks an API key with its provider using one cheap authenticated request, so an app can
/// refuse to store a key that does not work. Nothing is generated and nothing is billed.
///
/// A key that passes can still fail later for lack of credit or model access; this catches
/// mistyped, revoked, and wrong-provider keys.
public struct APIKeyValidator: Sendable {
    public enum Provider: Hashable, Sendable {
        /// `GET https://api.openai.com/v1/models`
        case openAI
        /// `GET https://openrouter.ai/api/v1/key`. The models list is public, so it cannot be used.
        case openRouter
        /// `GET https://api.typesafe.ai/v1/models`
        case jev
        /// `GET https://api.replicate.com/v1/account`
        case replicate

        var endpoint: String {
            switch self {
            case .openAI: "https://api.openai.com/v1/models"
            case .openRouter: "https://openrouter.ai/api/v1/key"
            case .jev: "https://api.typesafe.ai/v1/models"
            case .replicate: "https://api.replicate.com/v1/account"
            }
        }
    }

    public let provider: Provider
    public let timeoutInterval: TimeInterval
    private let session: URLSession

    public init(provider: Provider, timeoutInterval: TimeInterval = 20, session: URLSession = .shared) {
        self.provider = provider
        self.timeoutInterval = timeoutInterval
        self.session = session
    }

    /// Returns when the provider accepts the key. A rejected key throws `LLMError.http` with
    /// status 401 or 403 (see `LLMError.isRejectedCredential`); other statuses and transport
    /// failures (`URLError`) mean the key could not be checked, not that it is wrong.
    public func validate(_ apiKey: String) async throws {
        let request = try makeRequest(apiKey)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse("Expected an HTTP response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw DecisionService.httpError(http, data: data)
        }
    }

    func makeRequest(_ apiKey: String) throws -> URLRequest {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw LLMError.invalidConfiguration("An API key is required.") }
        guard let url = URL(string: provider.endpoint) else {
            throw LLMError.invalidConfiguration("The key-check URL could not be formed.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeoutInterval
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }
}

extension LLMError {
    /// True when the provider refused the credential itself (HTTP 401 or 403).
    public var isRejectedCredential: Bool {
        guard case .http(let status, _, _, _) = self else { return false }
        return status == 401 || status == 403
    }
}
