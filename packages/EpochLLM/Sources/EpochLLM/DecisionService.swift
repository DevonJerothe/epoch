import Foundation

/// A provider that answers `DecisionRequest`s. Register adapters on
/// `EpochAIManager` alongside text services.
public protocol EpochDecisionService: Sendable {
    var id: LLMServiceID { get }
    func decide(_ request: DecisionRequest) async throws -> DecisionResponse
}

/// One HTTP adapter for OpenAI Decisions, OpenRouter Decisions, and TypeSafe's
/// Jev API. Requests are never retried automatically; check
/// `LLMError.isRetryable` and apply your own backoff.
public struct DecisionService: EpochDecisionService {
    public let id: LLMServiceID
    public let endpoint: URL
    public let format: DecisionWireFormat
    public let timeoutInterval: TimeInterval
    private let apiKey: String
    private let headers: [String: String]
    private let session: URLSession

    /// `endpoint` is the full decision URL, e.g. https://api.typesafe.ai/v1/systemone.
    public init(
        id: LLMServiceID, endpoint: URL, format: DecisionWireFormat, apiKey: String,
        timeoutInterval: TimeInterval = 60, headers: [String: String] = [:],
        session: URLSession = .shared
    ) {
        self.id = id
        self.endpoint = endpoint
        self.format = format
        self.apiKey = apiKey
        self.timeoutInterval = timeoutInterval
        self.headers = headers
        self.session = session
    }

    /// OpenAI Decisions (public beta). The documented model is `gpt-6-luna`.
    public static func openAI(
        apiKey: String, timeoutInterval: TimeInterval = 60, session: URLSession = .shared
    ) -> Self {
        Self(id: .openAI, endpoint: URL(string: "https://api.openai.com/v1/decisions")!, format: .openAI,
             apiKey: apiKey, timeoutInterval: timeoutInterval, session: session)
    }

    /// OpenRouter Decisions (alpha). Use OpenRouter model IDs such as `typesafe/jev-1.13`.
    public static func openRouter(
        apiKey: String, timeoutInterval: TimeInterval = 60,
        appURL: URL? = nil, appName: String? = nil, session: URLSession = .shared
    ) -> Self {
        var headers: [String: String] = [:]
        headers["HTTP-Referer"] = appURL?.absoluteString
        headers["X-Title"] = appName
        return Self(id: .openRouter, endpoint: URL(string: "https://openrouter.ai/api/alpha/decisions")!,
                    format: .systemOne, apiKey: apiKey, timeoutInterval: timeoutInterval,
                    headers: headers, session: session)
    }

    /// TypeSafe's direct System One API. Use TypeSafe model IDs such as `jev-latest`.
    public static func jev(
        apiKey: String, timeoutInterval: TimeInterval = 60, session: URLSession = .shared
    ) -> Self {
        Self(id: .jev, endpoint: URL(string: "https://api.typesafe.ai/v1/systemone")!, format: .systemOne,
             apiKey: apiKey, timeoutInterval: timeoutInterval, session: session)
    }

    public func decide(_ request: DecisionRequest) async throws -> DecisionResponse {
        let urlRequest = try makeRequest(request)
        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse("Expected an HTTP response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw Self.httpError(http, data: data)
        }
        return try DecisionResponseParser.parse(data, for: request, format: format)
    }

    func makeRequest(_ request: DecisionRequest) throws -> URLRequest {
        guard ["http", "https"].contains(endpoint.scheme?.lowercased() ?? ""),
              endpoint.host != nil, endpoint.fragment == nil else {
            throw LLMError.invalidConfiguration("Use an HTTP(S) decision endpoint without a fragment.")
        }
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LLMError.invalidConfiguration("An API key is required for \(id.rawValue).")
        }
        guard timeoutInterval.isFinite, timeoutInterval > 0 else {
            throw LLMError.invalidConfiguration("The request timeout must be positive and finite.")
        }
        try request.validate(for: format)
        var result = URLRequest(url: endpoint)
        result.httpMethod = "POST"
        result.timeoutInterval = timeoutInterval
        for (name, value) in headers { result.setValue(value, forHTTPHeaderField: name) }
        result.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        result.setValue("application/json", forHTTPHeaderField: "Content-Type")
        result.setValue("application/json", forHTTPHeaderField: "Accept")
        result.httpBody = try JSONEncoder().encode(request.body(for: format))
        return result
    }

    /// Normalizes `{"error": {message, code}}` (OpenAI/OpenRouter) and
    /// `{"detail": ...}` (TypeSafe) bodies into `LLMError.http`.
    static func httpError(_ response: HTTPURLResponse, data: Data) -> LLMError {
        let root = (try? JSONDecoder().decode(JSONValue.self, from: data))?.object
        var message: String?
        var code: String?
        if let error = root?["error"]?.object {
            message = error["message"]?.string
            switch error["code"] {
            case .string(let value)?: code = value
            case .integer(let value)?: code = String(value)
            default: break
            }
        } else if let detail = root?["detail"] {
            switch detail {
            case .string(let value):
                message = value
            case .array(let items):
                // TypeSafe 422: [{loc: [...], msg, type}]
                let fields = items.compactMap(\.object)
                message = fields.map { item in
                    let location = (item["loc"]?.array ?? []).map { part -> String in
                        if case .integer(let index) = part { return String(index) }
                        return part.string ?? ""
                    }.joined(separator: ".")
                    let text = item["msg"]?.string ?? "Invalid value"
                    return location.isEmpty ? text : "\(location): \(text)"
                }.joined(separator: "; ")
                code = fields.first?["type"]?.string
            default:
                message = (try? JSONEncoder().encode(detail)).map { String(decoding: $0, as: UTF8.self) }
            }
        }
        if message?.isEmpty ?? true {
            message = HTTPURLResponse.localizedString(forStatusCode: response.statusCode)
        }
        return .http(
            status: response.statusCode, message: message ?? "", code: code,
            retryAfter: response.value(forHTTPHeaderField: "Retry-After")
        )
    }
}
