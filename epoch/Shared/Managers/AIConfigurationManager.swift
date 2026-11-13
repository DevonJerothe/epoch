import EpochLLM
import Foundation
import Observation

/// The narrator's provider. Raw values are persisted and match `LLMServiceID`s; do not change them.
nonisolated enum TextProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case openAI = "openai"
    case openRouter = "openrouter"
    /// Deterministic local responses. Development builds only.
    case fixture

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openAI: "OpenAI"
        case .openRouter: "OpenRouter"
        case .fixture: "Fixture"
        }
    }

    var credential: CredentialKind? {
        switch self {
        case .openAI: .openAI
        case .openRouter: .openRouter
        case .fixture: nil
        }
    }
}

/// The illustrator's provider. Raw values are persisted; do not change them.
nonisolated enum ImageProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case off
    case replicate
    /// Deterministic local images. Development builds only.
    case fixture

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .off: "Off"
        case .replicate: "Replicate"
        case .fixture: "Fixture"
        }
    }

    var credential: CredentialKind? {
        self == .replicate ? .replicate : nil
    }
}

/// The provider that answers classification and scoring questions about game state. Raw
/// values are persisted and match `LLMServiceID`s; do not change them.
nonisolated enum DecisionProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case openAI = "openai"
    case openRouter = "openrouter"
    case jev
    /// Deterministic local answers. Development builds only.
    case fixture

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openAI: "OpenAI"
        case .openRouter: "OpenRouter"
        case .jev: "Jev"
        case .fixture: "Fixture"
        }
    }

    /// OpenAI and OpenRouter reuse the narrator's key for that provider.
    var credential: CredentialKind? {
        switch self {
        case .openAI: .openAI
        case .openRouter: .openRouter
        case .jev: .jev
        case .fixture: nil
        }
    }
}

/// A role whose model the player chooses from the provider's list.
nonisolated enum ModelRole: String, Hashable, Sendable {
    case narrator
    case decisions

    var purpose: LLMModelPurpose {
        switch self {
        case .narrator: .text
        case .decisions: .decisions
        }
    }
}

/// Non-secret AI preferences, persisted in `UserDefaults`. API keys never belong here.
nonisolated struct AISettings: Codable, Equatable, Sendable {
    var textProvider: TextProvider = .openAI
    /// One model ID per provider, keyed by `TextProvider.rawValue`. Model IDs are
    /// provider-specific, so switching providers must not carry one across.
    var textModels: [String: String] = [:]
    var imageProvider: ImageProvider = .off
    var decisionProvider: DecisionProvider = .openAI
    /// One model ID per provider, keyed by `DecisionProvider.rawValue`. Kept apart from
    /// `textModels`: a provider's decision models are not its text models.
    var decisionModels: [String: String] = [:]

    init() {}

    /// Missing keys keep their defaults so settings saved by an older build still load.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        textProvider = try container.decodeIfPresent(TextProvider.self, forKey: .textProvider) ?? .openAI
        textModels = try container.decodeIfPresent([String: String].self, forKey: .textModels) ?? [:]
        imageProvider = try container.decodeIfPresent(ImageProvider.self, forKey: .imageProvider) ?? .off
        decisionProvider = try container.decodeIfPresent(DecisionProvider.self, forKey: .decisionProvider) ?? .openAI
        decisionModels = try container.decodeIfPresent([String: String].self, forKey: .decisionModels) ?? [:]
    }

    func model(for provider: DecisionProvider) -> String {
        decisionModels[provider.rawValue] ?? (provider == .fixture ? FixtureDecisionService.defaultModel : "")
    }

    func model(for provider: TextProvider) -> String {
        textModels[provider.rawValue] ?? (provider == .fixture ? FixtureTextService.defaultModel : "")
    }
}

nonisolated enum AIConfigurationError: LocalizedError, Equatable {
    case missingCredential(CredentialKind)
    case missingModel(TextProvider)
    case missingDecisionModel(DecisionProvider)
    case emptyCredential
    /// The provider refused the key when it was checked, so it was not saved.
    case rejectedCredential(CredentialKind)
    case imagesDisabled
    case fixturesUnavailable

    var title: String {
        switch self {
        case .missingCredential: "API key needed"
        case .missingModel, .missingDecisionModel: "Model needed"
        case .emptyCredential: "API key is empty"
        case .rejectedCredential: "API key rejected"
        case .imagesDisabled: "Illustrations are off"
        case .fixturesUnavailable: "Fixtures unavailable"
        }
    }

    /// True when the fix is to retype the key where it was entered, not to visit Settings.
    var isEntryProblem: Bool {
        switch self {
        case .emptyCredential, .rejectedCredential: true
        default: false
        }
    }

    var errorDescription: String? {
        switch self {
        case .missingCredential(let kind):
            "Add your \(kind.displayName) API key in Settings to continue."
        case .missingModel(let provider):
            "Enter a model ID for \(provider.displayName) in Settings to continue."
        case .missingDecisionModel(let provider):
            "Enter a decision model ID for \(provider.displayName) in Settings to continue."
        case .rejectedCredential(let kind):
            "\(kind.displayName) didn't accept this key, so it wasn't saved. Check it and try again."
        case .emptyCredential:
            "Paste an API key before saving."
        case .imagesDisabled:
            "Choose an illustrator in Settings to generate images."
        case .fixturesUnavailable:
            "Fixture responses are only available in development builds. Choose a provider in Settings."
        }
    }
}

/// Owns which AI providers and models the app uses, the Keychain-backed API keys for them, and
/// the `EpochAIManager` built from that configuration. Text, decisions, and images are
/// configured independently: a missing key for one never blocks the others.
@MainActor
@Observable
final class AIConfigurationManager {
    /// Ready-to-use text access. Build each `LLMRequest` with `model`.
    struct TextClient: Sendable {
        let manager: EpochAIManager
        let provider: TextProvider
        let model: String
    }

    /// Ready-to-use decision access. Build each `DecisionRequest` with `model`.
    struct DecisionClient: Sendable {
        let manager: EpochAIManager
        let provider: DecisionProvider
        let model: String
    }

    /// Builds the model catalog for a provider and its API key. Replaced in tests.
    typealias CatalogFactory = @Sendable (ModelCatalogService.Provider, String) -> any EpochModelCatalog

    /// Asks a provider whether a key works. Throws when it does not, or cannot be checked.
    typealias KeyValidator = @Sendable (CredentialKind, String) async throws -> Void

    static let shared = AIConfigurationManager()

    /// Launch with `-EpochAIFixtures YES` (development builds) to use fixtures for text,
    /// decisions, and images without touching saved settings, e.g. for UI tests and previews.
    nonisolated static let fixturesArgument = "EpochAIFixtures"
    nonisolated static let settingsKey = "ai.settings.v1"

    nonisolated static var isDevelopmentBuild: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    private(set) var settings: AISettings
    /// Which keys exist. The values themselves are never held in observable state.
    private(set) var storedCredentials: Set<CredentialKind> = []
    let fixturesAvailable: Bool
    let forcesFixtures: Bool

    @ObservationIgnored private let credentials: any CredentialStore
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let logger: LoggingManager
    @ObservationIgnored private let makeCatalog: CatalogFactory
    @ObservationIgnored private let validateKey: KeyValidator
    /// Model lists already fetched this launch, keyed by role and provider.
    @ObservationIgnored private var modelLists: [String: [LLMModelInfo]] = [:]
    @ObservationIgnored private var resolved: Resolved?
    /// Bumped on every change so a build that was in flight is not cached.
    @ObservationIgnored private var generation = 0

    init(
        credentials: any CredentialStore = KeychainCredentialStore(),
        defaults: UserDefaults = .standard,
        logger: LoggingManager = .shared,
        fixturesAvailable: Bool = AIConfigurationManager.isDevelopmentBuild,
        makeCatalog: @escaping CatalogFactory = AIConfigurationManager.liveCatalog,
        validateKey: @escaping KeyValidator = AIConfigurationManager.liveKeyValidation
    ) {
        self.makeCatalog = makeCatalog
        self.validateKey = validateKey
        self.credentials = credentials
        self.defaults = defaults
        self.logger = logger
        self.fixturesAvailable = fixturesAvailable
        forcesFixtures = fixturesAvailable && defaults.bool(forKey: Self.fixturesArgument)

        var loaded = AISettings()
        if let data = defaults.data(forKey: Self.settingsKey) {
            do {
                loaded = try JSONDecoder().decode(AISettings.self, from: data)
            } catch {
                // Unreadable settings fall back to defaults; keys in the Keychain are unaffected.
                ErrorManager.shared.report(error, context: "Loading AI settings", presentation: .logOnly)
            }
        }
        // A fixture selection saved by a development build must not strand a release build.
        if !fixturesAvailable {
            if loaded.textProvider == .fixture { loaded.textProvider = .openAI }
            if loaded.imageProvider == .fixture { loaded.imageProvider = .off }
            if loaded.decisionProvider == .fixture { loaded.decisionProvider = .openAI }
        }
        settings = loaded
    }

    nonisolated static func liveCatalog(
        _ provider: ModelCatalogService.Provider, apiKey: String
    ) -> any EpochModelCatalog {
        switch provider {
        case .openRouter: ModelCatalogService.openRouter(apiKey: apiKey.isEmpty ? nil : apiKey, appName: "Epoch")
        case .openAI, .jev: ModelCatalogService(provider: provider, apiKey: apiKey)
        }
    }

    nonisolated static func liveKeyValidation(_ kind: CredentialKind, apiKey: String) async throws {
        let provider: APIKeyValidator.Provider = switch kind {
        case .openAI: .openAI
        case .openRouter: .openRouter
        case .jev: .jev
        case .replicate: .replicate
        }
        try await APIKeyValidator(provider: provider).validate(apiKey)
    }

    // MARK: Providers and models

    var availableTextProviders: [TextProvider] {
        TextProvider.allCases.filter { $0 != .fixture || fixturesAvailable }
    }

    var availableDecisionProviders: [DecisionProvider] {
        DecisionProvider.allCases.filter { $0 != .fixture || fixturesAvailable }
    }

    var availableImageProviders: [ImageProvider] {
        ImageProvider.allCases.filter { $0 != .fixture || fixturesAvailable }
    }

    /// The provider requests actually use, after the fixtures launch argument is applied.
    var activeTextProvider: TextProvider { forcesFixtures ? .fixture : settings.textProvider }
    var activeImageProvider: ImageProvider { forcesFixtures ? .fixture : settings.imageProvider }
    var activeDecisionProvider: DecisionProvider { forcesFixtures ? .fixture : settings.decisionProvider }

    func selectTextProvider(_ provider: TextProvider) {
        guard availableTextProviders.contains(provider) else { return }
        update { $0.textProvider = provider }
    }

    func setTextModel(_ model: String, for provider: TextProvider) {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        update { $0.textModels[provider.rawValue] = trimmed.isEmpty ? nil : trimmed }
    }

    func selectDecisionProvider(_ provider: DecisionProvider) {
        guard availableDecisionProviders.contains(provider) else { return }
        update { $0.decisionProvider = provider }
    }

    func setDecisionModel(_ model: String, for provider: DecisionProvider) {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        update { $0.decisionModels[provider.rawValue] = trimmed.isEmpty ? nil : trimmed }
    }

    /// The model chosen for a role under its current provider, or "" when none is chosen.
    func selectedModel(for role: ModelRole) -> String {
        switch role {
        case .narrator: settings.model(for: settings.textProvider)
        case .decisions: settings.model(for: settings.decisionProvider)
        }
    }

    func selectModel(_ id: String, for role: ModelRole) {
        switch role {
        case .narrator: setTextModel(id, for: settings.textProvider)
        case .decisions: setDecisionModel(id, for: settings.decisionProvider)
        }
    }

    func providerName(for role: ModelRole) -> String {
        switch role {
        case .narrator: settings.textProvider.displayName
        case .decisions: settings.decisionProvider.displayName
        }
    }

    /// The models the role's provider offers, fetched from the provider's own models endpoint
    /// with the saved key. Results are kept for this launch; pass `refresh` to fetch again.
    /// Throws `AIConfigurationError.missingCredential` when the provider has no key yet,
    /// except for OpenRouter, whose list is public and loads without one.
    func availableModels(for role: ModelRole, refresh: Bool = false) async throws -> [LLMModelInfo] {
        let provider: ModelCatalogService.Provider
        let credential: CredentialKind
        let cacheKey: String
        switch role {
        case .narrator:
            cacheKey = "\(role.rawValue)|\(settings.textProvider.rawValue)"
            switch settings.textProvider {
            case .openAI: (provider, credential) = (.openAI, .openAI)
            case .openRouter: (provider, credential) = (.openRouter, .openRouter)
            case .fixture: return [FixtureTextService.modelInfo]
            }
        case .decisions:
            cacheKey = "\(role.rawValue)|\(settings.decisionProvider.rawValue)"
            switch settings.decisionProvider {
            case .openAI: (provider, credential) = (.openAI, .openAI)
            case .openRouter: (provider, credential) = (.openRouter, .openRouter)
            case .jev: (provider, credential) = (.jev, .jev)
            case .fixture: return [FixtureDecisionService.modelInfo]
            }
        }
        if !refresh, let cached = modelLists[cacheKey] { return cached }
        // An empty key means "none": OpenRouter lists its models to anyone.
        let key: String
        if provider == .openRouter {
            key = try await readCredential(credential) ?? ""
        } else {
            key = try await requiredCredential(credential)
        }
        let models = try await makeCatalog(provider, key).listModels(for: role.purpose)
        modelLists[cacheKey] = models
        logger.info("Model list loaded", category: .ai, metadata: [
            "role": role.rawValue, "count": String(models.count),
        ])
        return models
    }

    func selectImageProvider(_ provider: ImageProvider) {
        guard availableImageProviders.contains(provider) else { return }
        update { $0.imageProvider = provider }
    }

    private func update(_ change: (inout AISettings) -> Void) {
        var changed = settings
        change(&changed)
        guard changed != settings else { return }
        settings = changed
        invalidate()
        do {
            defaults.set(try JSONEncoder().encode(changed), forKey: Self.settingsKey)
            logger.info("AI settings changed", category: .settings, metadata: [
                "textProvider": changed.textProvider.rawValue,
                "decisionProvider": changed.decisionProvider.rawValue,
                "imageProvider": changed.imageProvider.rawValue,
            ])
        } catch {
            ErrorManager.shared.report(error, context: "Saving AI settings")
        }
    }

    // MARK: Credentials

    /// Loads which keys exist. Call before showing credential status.
    func refreshCredentialStatus() async throws {
        var stored: Set<CredentialKind> = []
        for kind in CredentialKind.allCases {
            if try await readCredential(kind) != nil { stored.insert(kind) }
        }
        storedCredentials = stored
    }

    /// Checks the key with its provider, then stores it. Throws
    /// `AIConfigurationError.rejectedCredential` when the provider refuses it; a network or
    /// provider failure during the check is rethrown as-is. Nothing is saved in either case.
    func saveCredential(_ value: String, for kind: CredentialKind) async throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AIConfigurationError.emptyCredential }
        // Registered first so no failure message, from the check or the write, can leak it.
        logger.redactor.register(trimmed)
        // A key the provider refuses, or that cannot be checked right now, is never stored.
        do {
            try await validateKey(kind, trimmed)
        } catch let error as LLMError where error.isRejectedCredential {
            logger.warning("API key rejected by provider", category: .settings, metadata: ["credential": kind.rawValue])
            throw AIConfigurationError.rejectedCredential(kind)
        }
        try await credentials.save(trimmed, for: kind)
        storedCredentials.insert(kind)
        invalidate()
        // A different key can belong to an account with different models.
        modelLists.removeAll()
        logger.info("API key saved", category: .settings, metadata: ["credential": kind.rawValue])
    }

    func removeCredential(for kind: CredentialKind) async throws {
        try await credentials.remove(kind)
        storedCredentials.remove(kind)
        invalidate()
        modelLists.removeAll()
        logger.info("API key removed", category: .settings, metadata: ["credential": kind.rawValue])
    }

    private func readCredential(_ kind: CredentialKind) async throws -> String? {
        guard let value = try await credentials.read(kind), !value.isEmpty else { return nil }
        logger.redactor.register(value)
        return value
    }

    private func requiredCredential(_ kind: CredentialKind) async throws -> String {
        guard let value = try await readCredential(kind) else {
            storedCredentials.remove(kind)
            throw AIConfigurationError.missingCredential(kind)
        }
        storedCredentials.insert(kind)
        return value
    }

    // MARK: Services

    /// Throws `AIConfigurationError` when the narrator's key or model is missing.
    func textClient() async throws -> TextClient {
        let resolved = await resolve()
        if let failure = resolved.textFailure { throw failure }
        let model = settings.model(for: resolved.textProvider)
        guard !model.isEmpty else { throw AIConfigurationError.missingModel(resolved.textProvider) }
        return TextClient(manager: resolved.manager, provider: resolved.textProvider, model: model)
    }

    /// Throws `AIConfigurationError` when the decision provider's key or model is missing.
    func decisionClient() async throws -> DecisionClient {
        let resolved = await resolve()
        if let failure = resolved.decisionFailure { throw failure }
        let model = settings.model(for: resolved.decisionProvider)
        guard !model.isEmpty else {
            throw AIConfigurationError.missingDecisionModel(resolved.decisionProvider)
        }
        return DecisionClient(manager: resolved.manager, provider: resolved.decisionProvider, model: model)
    }

    /// Throws `AIConfigurationError` when illustrations are off or the key is missing.
    func generateImage(_ request: ImageGenerationRequest) async throws -> ImageGenerationResponse {
        let resolved = await resolve()
        if let failure = resolved.imageFailure { throw failure }
        return try await resolved.manager.generateImage(request)
    }

    private struct Resolved {
        let manager: EpochAIManager
        let textProvider: TextProvider
        let textFailure: (any Error)?
        let decisionProvider: DecisionProvider
        let decisionFailure: (any Error)?
        let imageFailure: (any Error)?
    }

    private func invalidate() {
        generation += 1
        resolved = nil
    }

    /// Builds one `EpochAIManager` from the current configuration and caches it until the
    /// configuration changes. A side that cannot be built records why instead of failing the other.
    private func resolve() async -> Resolved {
        while true {
            if let resolved { return resolved }
            let startedAt = generation
            let textProvider = activeTextProvider
            let decisionProvider = activeDecisionProvider
            let imageProvider = activeImageProvider

            var textFailure: (any Error)?
            let textService: any EpochLLMService
            do {
                textService = try await makeTextService(textProvider)
            } catch {
                textFailure = error
                textService = UnavailableTextService(
                    id: LLMServiceID(rawValue: textProvider.rawValue), failure: error
                )
            }

            var decisionFailure: (any Error)?
            var decisionService: (any EpochDecisionService)?
            do {
                decisionService = try await makeDecisionService(decisionProvider)
            } catch {
                decisionFailure = error
            }

            var imageFailure: (any Error)?
            var imageService: (any EpochImageService)?
            do {
                imageService = try await makeImageService(imageProvider)
            } catch {
                imageFailure = error
            }

            // The configuration changed while keys were being read; build again from the new one.
            guard startedAt == generation else { continue }
            let built = Resolved(
                manager: EpochAIManager(
                    service: textService, imageService: imageService, decisionService: decisionService
                ),
                textProvider: textProvider, textFailure: textFailure,
                decisionProvider: decisionProvider, decisionFailure: decisionFailure,
                imageFailure: imageFailure
            )
            resolved = built
            return built
        }
    }

    private func makeTextService(_ provider: TextProvider) async throws -> any EpochLLMService {
        switch provider {
        case .openAI:
            return ResponsesService.openAI(apiKey: try await requiredCredential(.openAI))
        case .openRouter:
            return ResponsesService.openRouter(apiKey: try await requiredCredential(.openRouter), appName: "Epoch")
        case .fixture:
            guard fixturesAvailable else { throw AIConfigurationError.fixturesUnavailable }
            return FixtureTextService()
        }
    }

    private func makeDecisionService(_ provider: DecisionProvider) async throws -> any EpochDecisionService {
        switch provider {
        case .openAI:
            return DecisionService.openAI(apiKey: try await requiredCredential(.openAI))
        case .openRouter:
            return DecisionService.openRouter(apiKey: try await requiredCredential(.openRouter), appName: "Epoch")
        case .jev:
            return DecisionService.jev(apiKey: try await requiredCredential(.jev))
        case .fixture:
            guard fixturesAvailable else { throw AIConfigurationError.fixturesUnavailable }
            return FixtureDecisionService()
        }
    }

    private func makeImageService(_ provider: ImageProvider) async throws -> any EpochImageService {
        switch provider {
        case .off:
            throw AIConfigurationError.imagesDisabled
        case .replicate:
            return ReplicateImageService(apiKey: try await requiredCredential(.replicate))
        case .fixture:
            guard fixturesAvailable else { throw AIConfigurationError.fixturesUnavailable }
            return FixtureImageService()
        }
    }
}

/// Fills the text slot `EpochAIManager` requires while the narrator is not configured, so
/// images can still be used. Any request made through it fails with the configuration error.
private nonisolated struct UnavailableTextService: EpochLLMService {
    let id: LLMServiceID
    let failure: any Error

    func send(_ request: LLMRequest) async throws -> LLMResponse {
        throw failure
    }

    func stream(_ request: LLMRequest) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        AsyncThrowingStream { $0.finish(throwing: failure) }
    }
}
