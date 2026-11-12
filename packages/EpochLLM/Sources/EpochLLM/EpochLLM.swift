import Foundation

/// Open-ended identifiers allow adapters for local models and future providers.
public struct LLMServiceID: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let openAI = Self(rawValue: "openai")
    public static let openRouter = Self(rawValue: "openrouter")
    /// TypeSafe's direct Jev API (decisions only).
    public static let jev = Self(rawValue: "jev")
}

/// A provider translates Epoch's shared models to its transport format.
public protocol EpochLLMService: Sendable {
    var id: LLMServiceID { get }
    func send(_ request: LLMRequest) async throws -> LLMResponse
    func stream(_ request: LLMRequest) -> AsyncThrowingStream<LLMStreamEvent, Error>
}

/// One manager for all providers. Selection affects new requests only; in-flight
/// requests retain their service. Conversation history belongs to the caller.
public actor EpochAIManager {
    private var services: [LLMServiceID: any EpochLLMService]
    public private(set) var selectedService: LLMServiceID
    private var imageService: ReplicateImageService?
    private var decisionServices: [LLMServiceID: any EpochDecisionService] = [:]
    /// Selected independently of the text service; the first registered decision
    /// service is selected until `selectDecisionService(_:)` is called.
    public private(set) var selectedDecisionService: LLMServiceID?

    public init(
        service: any EpochLLMService, imageService: ReplicateImageService? = nil,
        decisionService: (any EpochDecisionService)? = nil
    ) {
        services = [service.id: service]
        selectedService = service.id
        self.imageService = imageService
        if let decisionService {
            decisionServices[decisionService.id] = decisionService
            selectedDecisionService = decisionService.id
        }
    }

    public func registerDecisionService(_ service: any EpochDecisionService) {
        decisionServices[service.id] = service
        if selectedDecisionService == nil { selectedDecisionService = service.id }
    }

    public func selectDecisionService(_ id: LLMServiceID) throws {
        guard decisionServices[id] != nil else { throw LLMError.unregisteredService(id) }
        selectedDecisionService = id
    }

    /// Asks the selected (or given) decision service. Model IDs belong to that provider.
    public func decide(_ request: DecisionRequest, using id: LLMServiceID? = nil) async throws -> DecisionResponse {
        guard let id = id ?? selectedDecisionService else {
            throw LLMError.invalidConfiguration("Register a decision service before requesting decisions.")
        }
        guard let provider = decisionServices[id] else { throw LLMError.unregisteredService(id) }
        return try await provider.decide(request)
    }

    public func configureImageGeneration(_ service: ReplicateImageService) {
        imageService = service
    }

    /// Image generation uses Replicate independently of the selected text service.
    public func generateImage(_ request: ImageGenerationRequest) async throws -> ImageGenerationResponse {
        guard let provider = imageService else {
            throw LLMError.invalidConfiguration("Configure a Replicate image service before generating images.")
        }
        return try await provider.generateImage(request)
    }

    public func register(_ service: any EpochLLMService) {
        services[service.id] = service
    }

    public func select(_ id: LLMServiceID) throws {
        _ = try service(for: id)
        selectedService = id
    }

    public func send(_ request: LLMRequest, using id: LLMServiceID? = nil) async throws -> LLMResponse {
        let provider = try service(for: id ?? selectedService)
        return try await provider.send(request)
    }

    public func stream(
        _ request: LLMRequest, using id: LLMServiceID? = nil
    ) throws -> AsyncThrowingStream<LLMStreamEvent, Error> {
        try service(for: id ?? selectedService).stream(request)
    }

    private func service(for id: LLMServiceID) throws -> any EpochLLMService {
        guard let service = services[id] else { throw LLMError.unregisteredService(id) }
        return service
    }
}

public enum LLMError: Error, LocalizedError, Sendable {
    case unregisteredService(LLMServiceID)
    case invalidConfiguration(String)
    case invalidResponse(String)
    case http(status: Int, message: String, code: String?, retryAfter: String?)
    case responseFailed(message: String, code: String?)
    case interruptedStream

    public var errorDescription: String? {
        switch self {
        case .unregisteredService(let id): "No service registered for \(id.rawValue)."
        case .invalidConfiguration(let message), .invalidResponse(let message): message
        case .http(let status, let message, _, _): "HTTP \(status): \(message)"
        case .responseFailed(let message, _): message
        case .interruptedStream: "The stream ended without a final response."
        }
    }

    /// True for rate limits, timeouts, and transient server/overload statuses
    /// (e.g. 429, 529). The SDK never retries; callers choose a backoff policy
    /// and should honor `retryAfter` when present.
    public var isRetryable: Bool {
        guard case .http(let status, _, _, _) = self else { return false }
        return [408, 429, 500, 502, 503, 504, 524, 529].contains(status)
    }
}
