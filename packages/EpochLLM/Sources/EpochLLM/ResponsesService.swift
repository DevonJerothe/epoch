import Foundation

/// OpenAI and OpenRouter share this adapter. A provider with a different wire
/// format (e.g. LM Studio REST) implements EpochLLMService independently.
public struct ResponsesService: EpochLLMService {
    public let id: LLMServiceID
    public let baseURL: URL
    public let timeoutInterval: TimeInterval
    private let apiKey: String
    private let headers: [String: String]
    private let session: URLSession

    /// baseURL includes the API prefix, e.g. https://api.openai.com/v1.
    public init(
        id: LLMServiceID, baseURL: URL, apiKey: String,
        timeoutInterval: TimeInterval = 120, headers: [String: String] = [:],
        session: URLSession = .shared
    ) {
        self.id = id
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.timeoutInterval = timeoutInterval
        self.headers = headers
        self.session = session
    }

    public static func openAI(
        apiKey: String, timeoutInterval: TimeInterval = 120, session: URLSession = .shared
    ) -> Self {
        Self(id: .openAI, baseURL: URL(string: "https://api.openai.com/v1")!,
             apiKey: apiKey, timeoutInterval: timeoutInterval, session: session)
    }

    public static func openRouter(
        apiKey: String, timeoutInterval: TimeInterval = 120,
        appURL: URL? = nil, appName: String? = nil, session: URLSession = .shared
    ) -> Self {
        var headers: [String: String] = [:]
        headers["HTTP-Referer"] = appURL?.absoluteString
        headers["X-Title"] = appName
        return Self(id: .openRouter, baseURL: URL(string: "https://openrouter.ai/api/v1")!,
                    apiKey: apiKey, timeoutInterval: timeoutInterval, headers: headers, session: session)
    }

    public func send(_ request: LLMRequest) async throws -> LLMResponse {
        let urlRequest = try makeRequest(request, streaming: false)
        let (data, response) = try await session.data(for: urlRequest)
        let http = try httpResponse(response)
        guard (200..<300).contains(http.statusCode) else { throw httpError(http, data: data) }
        return try JSONDecoder().decode(LLMResponse.self, from: data).validated()
    }

    public func stream(_ request: LLMRequest) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let urlRequest = try makeRequest(request, streaming: true)
                    let (bytes, response) = try await session.bytes(for: urlRequest)
                    defer { bytes.task.cancel() }
                    let http = try httpResponse(response)
                    guard (200..<300).contains(http.statusCode) else {
                        var body = Data()
                        for try await byte in bytes {
                            body.append(byte)
                            if body.count >= 65_536 { break }
                        }
                        throw httpError(http, data: body)
                    }
                    guard http.value(forHTTPHeaderField: "Content-Type")?
                        .lowercased().contains("text/event-stream") == true else {
                        throw LLMError.invalidResponse("Expected a text/event-stream response.")
                    }
                    var parser = ServerSentEventParser()
                    for try await byte in bytes {
                        try Task.checkCancellation()
                        guard let data = try parser.append(byte) else { continue }
                        if try emit(data, to: continuation) {
                            continuation.finish()
                            return
                        }
                    }
                    if let data = try parser.finish(), try emit(data, to: continuation) {
                        continuation.finish()
                        return
                    }
                    throw LLMError.interruptedStream
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    func makeRequest(_ request: LLMRequest, streaming: Bool) throws -> URLRequest {
        guard ["http", "https"].contains(baseURL.scheme?.lowercased() ?? ""),
              baseURL.host != nil, baseURL.query == nil, baseURL.fragment == nil else {
            throw LLMError.invalidConfiguration("Use an HTTP(S) API base URL without a query or fragment.")
        }
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LLMError.invalidConfiguration("An API key is required for \(id.rawValue).")
        }
        guard timeoutInterval.isFinite, timeoutInterval > 0 else {
            throw LLMError.invalidConfiguration("The request timeout must be positive and finite.")
        }
        guard !request.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LLMError.invalidConfiguration("A model ID is required.")
        }
        var result = URLRequest(url: baseURL.appendingPathComponent("responses"))
        result.httpMethod = "POST"
        result.timeoutInterval = timeoutInterval
        for (name, value) in headers { result.setValue(value, forHTTPHeaderField: name) }
        result.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        result.setValue("application/json", forHTTPHeaderField: "Content-Type")
        result.setValue(streaming ? "text/event-stream" : "application/json", forHTTPHeaderField: "Accept")
        result.httpBody = try JSONEncoder().encode(WireRequest(request: request, stream: streaming))
        return result
    }

    private func httpResponse(_ response: URLResponse) throws -> HTTPURLResponse {
        guard let http = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse("Expected an HTTP response.")
        }
        return http
    }

    private func httpError(_ response: HTTPURLResponse, data: Data) -> LLMError {
        struct Envelope: Decodable { let error: LLMResponseError }
        let error = try? JSONDecoder().decode(Envelope.self, from: data).error
        return .http(
            status: response.statusCode,
            message: error?.message ?? HTTPURLResponse.localizedString(forStatusCode: response.statusCode),
            code: error?.code, retryAfter: response.value(forHTTPHeaderField: "Retry-After")
        )
    }

    /// Returns true only for a terminal response; [DONE] alone is not success.
    private func emit(
        _ data: Data, to continuation: AsyncThrowingStream<LLMStreamEvent, Error>.Continuation
    ) throws -> Bool {
        guard let event = try ResponsesStreamDecoder.decode(data) else { return false }
        continuation.yield(event)
        if case .response = event { return true }
        return false
    }
}

private struct WireRequest: Encodable {
    let request: LLMRequest
    let stream: Bool
    enum CodingKeys: String, CodingKey { case stream }
    func encode(to encoder: Encoder) throws {
        try request.encode(to: encoder)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(stream, forKey: .stream)
    }
}
