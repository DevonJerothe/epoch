import Foundation

/// What a model will be used for. Providers list and filter models differently for each.
public enum LLMModelPurpose: String, Hashable, Sendable {
    /// Narration through the Responses API.
    case text
    /// Classification and scoring through a Decisions API.
    case decisions
}

/// One selectable model. Only `id` is guaranteed: each provider reports different details,
/// and a field is `nil` when that provider's models endpoint does not return it.
public struct LLMModelInfo: Equatable, Identifiable, Sendable {
    /// The value to send as a request's `model`.
    public let id: String
    /// Display name (OpenRouter).
    public var name: String?
    /// What the model is for (OpenRouter, TypeSafe).
    public var summary: String?
    /// Owning organization (OpenAI).
    public var owner: String?
    /// When the model was added (OpenAI, OpenRouter) or released (TypeSafe).
    public var released: Date?
    /// Context window in tokens (OpenRouter).
    public var contextLength: Int?
    /// Token prices (OpenRouter).
    public var pricing: LLMModelPricing?
    /// Announced shutdown or expiration date, `YYYY-MM-DD` (OpenAI, OpenRouter).
    public var retirementDate: String?
    /// The model an alias currently resolves to (OpenRouter `~…-latest` aliases).
    public var aliasTarget: String?

    public init(
        id: String, name: String? = nil, summary: String? = nil, owner: String? = nil,
        released: Date? = nil, contextLength: Int? = nil, pricing: LLMModelPricing? = nil,
        retirementDate: String? = nil, aliasTarget: String? = nil
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.owner = owner
        self.released = released
        self.contextLength = contextLength
        self.pricing = pricing
        self.retirementDate = retirementDate
        self.aliasTarget = aliasTarget
    }
}

/// US dollars per million tokens. Either side is `nil` when the provider omits it.
public struct LLMModelPricing: Equatable, Sendable {
    public var inputPerMillionTokens: Double?
    public var outputPerMillionTokens: Double?

    public init(inputPerMillionTokens: Double?, outputPerMillionTokens: Double?) {
        self.inputPerMillionTokens = inputPerMillionTokens
        self.outputPerMillionTokens = outputPerMillionTokens
    }
}

/// A source of selectable models. Apps can supply their own, e.g. fixtures.
public protocol EpochModelCatalog: Sendable {
    func listModels(for purpose: LLMModelPurpose) async throws -> [LLMModelInfo]
}

/// Lists models from each provider's own endpoint. Nothing is cached and nothing is retried.
///
/// - OpenAI `GET /v1/models` returns only `id`, `created`, `owned_by`, and `shutdown_date`.
///   It has no capability field or filter, so `.text` hides models whose ID marks them as
///   something other than a text model (`openAINonTextModelMarkers`), and `.decisions` keeps
///   the models OpenAI's Decisions reference documents (`openAIDecisionModelPrefixes`).
/// - OpenRouter `GET /api/v1/models` is public, so it needs no key. It is filtered server-side to models served on the endpoint
///   Epoch calls, and reports names, descriptions, context length, and per-token prices.
/// - TypeSafe `GET /v1/models` lists the Jev aliases available to the account with a
///   description and release date. It serves decisions only.
public struct ModelCatalogService: EpochModelCatalog {
    public enum Provider: Hashable, Sendable {
        case openAI, openRouter, jev
    }

    /// OpenAI's Decisions reference says only `gpt-6-luna` is supported. Update this when
    /// that changes; the models endpoint cannot tell us.
    public static let openAIDecisionModelPrefixes = ["gpt-6-luna"]

    /// ID fragments of OpenAI models that cannot narrate: embeddings, audio, images, video,
    /// moderation, and Chat Completions search models. This is a naming heuristic, because the models endpoint reports no
    /// capabilities; a text model whose ID contains one of these would be hidden too.
    public static let openAINonTextModelMarkers = [
        "embedding", "audio", "tts", "whisper", "transcribe", "realtime",
        "image", "dall-e", "sora", "moderation",
        // Search models belong to the Chat Completions search path, not the Responses route.
        "search-api", "search-preview",
    ]

    static func isOpenAITextModel(_ id: String) -> Bool {
        let id = id.lowercased()
        return !openAINonTextModelMarkers.contains { id.contains($0) }
    }

    /// OpenRouter pages hold at most this many models; listing stops after `maximumPages`.
    static let pageSize = 500
    static let maximumPages = 20

    public let provider: Provider
    public let timeoutInterval: TimeInterval
    private let apiKey: String?
    private let headers: [String: String]
    private let session: URLSession

    /// `apiKey` may be `nil` for OpenRouter only; the other providers require one.
    public init(
        provider: Provider, apiKey: String?, timeoutInterval: TimeInterval = 30,
        headers: [String: String] = [:], session: URLSession = .shared
    ) {
        self.provider = provider
        self.apiKey = apiKey
        self.timeoutInterval = timeoutInterval
        self.headers = headers
        self.session = session
    }

    public static func openAI(apiKey: String, session: URLSession = .shared) -> Self {
        Self(provider: .openAI, apiKey: apiKey, session: session)
    }

    /// The key is optional: OpenRouter lists its models to anyone.
    public static func openRouter(
        apiKey: String? = nil, appURL: URL? = nil, appName: String? = nil, session: URLSession = .shared
    ) -> Self {
        var headers: [String: String] = [:]
        headers["HTTP-Referer"] = appURL?.absoluteString
        headers["X-Title"] = appName
        return Self(provider: .openRouter, apiKey: apiKey, headers: headers, session: session)
    }

    public static func jev(apiKey: String, session: URLSession = .shared) -> Self {
        Self(provider: .jev, apiKey: apiKey, session: session)
    }

    public func listModels(for purpose: LLMModelPurpose) async throws -> [LLMModelInfo] {
        guard provider == .openRouter || usableKey != nil else {
            throw LLMError.invalidConfiguration("An API key is required to list models.")
        }
        switch provider {
        case .openAI: return try await listOpenAI(purpose)
        case .openRouter: return try await listOpenRouter(purpose)
        case .jev:
            guard purpose == .decisions else {
                throw LLMError.invalidConfiguration("Jev models answer decisions only.")
            }
            return try await listJev()
        }
    }

    // MARK: OpenAI

    private func listOpenAI(_ purpose: LLMModelPurpose) async throws -> [LLMModelInfo] {
        struct Page: Decodable {
            struct Model: Decodable {
                let id: String
                let created: Double?
                let ownedBy: String?
                let shutdownDate: String?
                enum CodingKeys: String, CodingKey {
                    case id, created
                    case ownedBy = "owned_by", shutdownDate = "shutdown_date"
                }
            }
            let data: [Model]
        }
        let page: Page = try await fetch(try Self.url("https://api.openai.com/v1/models"))
        return page.data
            .filter { model in
                switch purpose {
                case .text: Self.isOpenAITextModel(model.id)
                case .decisions: Self.openAIDecisionModelPrefixes.contains { model.id.hasPrefix($0) }
                }
            }
            .map { model in
                LLMModelInfo(
                    id: model.id, owner: model.ownedBy,
                    released: model.created.map { Date(timeIntervalSince1970: $0) },
                    retirementDate: model.shutdownDate
                )
            }
            // Newest first; the endpoint's own order is not documented.
            .sorted { ($0.released ?? .distantPast, $1.id) > ($1.released ?? .distantPast, $0.id) }
    }

    // MARK: OpenRouter

    static func openRouterURL(for purpose: LLMModelPurpose) throws -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "openrouter.ai"
        components.path = "/api/v1/models"
        var query = [URLQueryItem(name: "limit", value: String(pageSize))]
        switch purpose {
        case .text:
            // Epoch narrates through the Responses route.
            query.append(URLQueryItem(name: "endpoints", value: "/api/v1/responses"))
            query.append(URLQueryItem(name: "output_modalities", value: "text"))
        case .decisions:
            query.append(URLQueryItem(name: "endpoints", value: "/api/alpha/decisions"))
            // The endpoint lists only text-output models unless asked otherwise.
            query.append(URLQueryItem(name: "output_modalities", value: "decisions"))
        }
        components.queryItems = query
        guard let url = components.url else {
            throw LLMError.invalidConfiguration("The OpenRouter models URL could not be formed.")
        }
        return url
    }

    private func listOpenRouter(_ purpose: LLMModelPurpose) async throws -> [LLMModelInfo] {
        struct Page: Decodable {
            struct Model: Decodable {
                struct Pricing: Decodable {
                    let prompt: String?
                    let completion: String?
                }
                struct Alias: Decodable {
                    let slug: String
                }
                let id: String
                let name: String?
                let description: String?
                let created: Double?
                let contextLength: Int?
                let pricing: Pricing?
                let expirationDate: String?
                let aliasTarget: Alias?
                enum CodingKeys: String, CodingKey {
                    case id, name, description, created, pricing
                    case contextLength = "context_length", expirationDate = "expiration_date"
                    case aliasTarget = "alias_target"
                }
            }
            struct Links: Decodable {
                let next: String?
            }
            let data: [Model]
            let links: Links?
        }
        var models: [LLMModelInfo] = []
        var seen: Set<String> = []
        var next: URL? = try Self.openRouterURL(for: purpose)
        var pages = 0
        while let url = next, pages < Self.maximumPages {
            pages += 1
            let page: Page = try await fetch(url)
            for model in page.data where seen.insert(model.id).inserted {
                models.append(LLMModelInfo(
                    id: model.id, name: model.name, summary: model.description,
                    released: model.created.map { Date(timeIntervalSince1970: $0) },
                    contextLength: model.contextLength,
                    pricing: model.pricing.flatMap { Self.pricing(prompt: $0.prompt, completion: $0.completion) },
                    retirementDate: model.expirationDate, aliasTarget: model.aliasTarget?.slug
                ))
            }
            // `links.next` is a path relative to the host, or null on the last page.
            next = try page.links?.next.flatMap { path -> URL? in
                guard !page.data.isEmpty else { return nil }
                guard let resolved = URL(string: path, relativeTo: url)?.absoluteURL,
                      resolved.host == url.host, resolved.scheme == "https" else {
                    throw LLMError.invalidResponse("OpenRouter returned an unexpected next-page link.")
                }
                return resolved
            }
        }
        return models
    }

    /// OpenRouter prices are decimal strings in USD per token.
    static func pricing(prompt: String?, completion: String?) -> LLMModelPricing? {
        func perMillion(_ value: String?) -> Double? {
            guard let value, let decimal = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")),
                  decimal >= 0 else { return nil }
            return NSDecimalNumber(decimal: decimal * 1_000_000).doubleValue
        }
        let input = perMillion(prompt)
        let output = perMillion(completion)
        guard input != nil || output != nil else { return nil }
        return LLMModelPricing(inputPerMillionTokens: input, outputPerMillionTokens: output)
    }

    // MARK: TypeSafe

    private func listJev() async throws -> [LLMModelInfo] {
        struct Page: Decodable {
            struct Model: Decodable {
                let name: String
                let description: String?
                let releaseDate: String?
                enum CodingKeys: String, CodingKey {
                    case name, description
                    case releaseDate = "release_date"
                }
            }
            let models: [Model]
        }
        let page: Page = try await fetch(try Self.url("https://api.typesafe.ai/v1/models"))
        return page.models.map { model in
            LLMModelInfo(
                id: model.name, summary: model.description,
                released: model.releaseDate.flatMap(Self.date(fromDay:))
            )
        }
    }

    static func date(fromDay day: String) -> Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? calendar.timeZone
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    // MARK: Transport

    private static func url(_ string: String) throws -> URL {
        guard let url = URL(string: string) else {
            throw LLMError.invalidConfiguration("The models URL could not be formed.")
        }
        return url
    }

    func makeRequest(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeoutInterval
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        if let usableKey { request.setValue("Bearer \(usableKey)", forHTTPHeaderField: "Authorization") }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private var usableKey: String? {
        let trimmed = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func fetch<T: Decodable>(_ url: URL) async throws -> T {
        let (data, response) = try await session.data(for: makeRequest(url))
        guard let http = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse("Expected an HTTP response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw DecisionService.httpError(http, data: data)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw LLMError.invalidResponse("The provider's model list could not be read.")
        }
    }
}
