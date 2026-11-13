import EpochLLM
import Foundation
import os
import Testing
@testable import epoch

private nonisolated final class RecordingSink: LogSink, Sendable {
    private let recorded = OSAllocatedUnfairLock(initialState: [LogEntry]())

    var entries: [LogEntry] { recorded.withLock { $0 } }

    func record(_ entry: LogEntry) {
        recorded.withLock { $0.append(entry) }
    }
}

private nonisolated struct UnknownFailure: Error {}

@MainActor
struct LoggingTests {
    @Test func redactsKnownKeyShapes() {
        let redactor = LogRedactor()
        let samples = [
            "Authorization: Bearer abc123def456ghi789",
            "Incorrect API key provided: sk-proj-abcdefgh12345678",
            "key sk-or-v1-0123456789abcdef rejected",
            "token r8_abcdefgh12345678 expired",
            #"{"api_key": "plainvalue123"}"#,
        ]
        for sample in samples {
            let redacted = redactor.redact(sample)
            #expect(redacted.contains(LogRedactor.placeholder), "\(sample)")
            for secret in ["abc123def456ghi789", "abcdefgh12345678", "0123456789abcdef", "plainvalue123"] {
                #expect(!redacted.contains(secret), "\(sample)")
            }
        }
    }

    @Test func redactsRegisteredSecretsOfAnyShape() {
        let redactor = LogRedactor()
        redactor.register("  unusual/shape+value==  ")
        #expect(redactor.redact("sent unusual/shape+value== to host") == "sent \(LogRedactor.placeholder) to host")
    }

    @Test func leavesOrdinaryTextAlone() {
        let redactor = LogRedactor()
        redactor.register("short")
        let text = "max_output_tokens: 800, 12 input tokens, a short risk-free task"
        #expect(redactor.redact(text) == text)
    }

    @Test func sinksReceiveRedactedEntries() {
        let sink = RecordingSink()
        let logger = LoggingManager(sinks: [sink])
        logger.redactor.register("my-secret-value")
        logger.error("failed with my-secret-value", category: .ai, metadata: ["header": "Bearer zzzzzzzzzzzz"])
        logger.track("story_started", properties: ["world": "abbey"])

        let entries = sink.entries
        #expect(entries.count == 2)
        #expect(entries[0].level == .error)
        #expect(entries[0].category == .ai)
        #expect(entries[0].message == "failed with \(LogRedactor.placeholder)")
        #expect(entries[0].metadata["header"] == "Bearer \(LogRedactor.placeholder)")
        #expect(entries[1].category == .analytics)
        #expect(entries[1].message == "story_started")
        #expect(entries[1].metadata == ["world": "abbey"])
    }
}

@MainActor
struct ErrorManagerTests {
    @Test func describesConfigurationAndRequestFailures() {
        #expect(ErrorDescription.describe(AIConfigurationError.missingCredential(.openAI))?.recovery == .openSettings)
        #expect(ErrorDescription.describe(AIConfigurationError.missingModel(.openRouter))?.recovery == .openSettings)
        #expect(ErrorDescription.describe(LLMError.invalidConfiguration("A model ID is required."))?.recovery == .openSettings)

        let rejected = ErrorDescription.describe(LLMError.http(status: 401, message: "bad key", code: nil, retryAfter: nil))
        #expect(rejected?.title == "API key rejected")
        #expect(rejected?.recovery == .openSettings)

        let missingModel = ErrorDescription.describe(
            LLMError.http(status: 400, message: "no such model", code: "model_not_found", retryAfter: nil)
        )
        #expect(missingModel?.recovery == .openSettings)

        let limited = ErrorDescription.describe(LLMError.http(status: 429, message: "slow down", code: nil, retryAfter: "12"))
        #expect(limited?.recovery == .retry)
        #expect(limited?.message.contains("12 seconds") == true)

        #expect(ErrorDescription.describe(LLMError.http(status: 503, message: "", code: nil, retryAfter: nil))?.recovery == .retry)
        #expect(ErrorDescription.describe(URLError(.notConnectedToInternet))?.title == "No connection")
        #expect(ErrorDescription.describe(UnknownFailure())?.recovery == .retry)
    }

    @Test func cancellationsAreNotErrors() {
        #expect(ErrorDescription.describe(CancellationError()) == nil)
        #expect(ErrorDescription.describe(URLError(.cancelled)) == nil)

        let errors = ErrorManager(logger: LoggingManager())
        errors.report(CancellationError(), context: "Narration")
        #expect(errors.banner == nil)
        #expect(errors.latestError == nil)
    }

    @Test func presentsBannerAlertOrNothing() {
        let errors = ErrorManager(logger: LoggingManager())

        errors.report(AIConfigurationError.missingCredential(.openAI), context: "Narration")
        #expect(errors.banner?.offersSettings == true)
        #expect(errors.banner?.offersRetry == false)
        #expect(errors.alert == nil)

        errors.report(URLError(.timedOut), context: "Narration", presentation: .alert) {}
        #expect(errors.alert?.offersRetry == true)
        errors.dismissAlert()
        #expect(errors.alert == nil)

        // A retryable error with no retry closure has nothing to offer.
        errors.report(URLError(.timedOut), context: "Narration")
        #expect(errors.banner?.offersRetry == false)

        errors.clear()
        errors.report(UnknownFailure(), context: "Background work", presentation: .logOnly)
        #expect(errors.banner == nil)
        #expect(errors.latestError is UnknownFailure)
        #expect(errors.context == "Background work")
    }

    @Test func logsAndShowsRedactedText() {
        let sink = RecordingSink()
        let logger = LoggingManager(sinks: [sink])
        let errors = ErrorManager(logger: logger)
        let key = "sk-proj-abcdefgh12345678"

        errors.report(
            LLMError.http(status: 500, message: "echo \(key)", code: "boom", retryAfter: nil),
            context: "Narration with \(key)"
        )
        errors.report(LLMError.responseFailed(message: "echo \(key)", code: nil), context: "Narration")

        #expect(sink.entries.count == 2)
        for entry in sink.entries {
            #expect(entry.level == .error)
            #expect(!entry.message.contains(key))
            #expect(!entry.metadata.values.contains { $0.contains(key) })
        }
        #expect(errors.banner?.message.contains(key) == false)
        #expect(errors.banner?.message.contains(LogRedactor.placeholder) == true)
    }
}

@MainActor
struct AIConfigurationTests {
    private func makeDefaults() throws -> UserDefaults {
        let name = "epoch.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func makeManager(
        _ store: any CredentialStore = InMemoryCredentialStore(), defaults: UserDefaults,
        fixturesAvailable: Bool = true
    ) -> AIConfigurationManager {
        AIConfigurationManager(
            credentials: store, defaults: defaults, logger: LoggingManager(), fixturesAvailable: fixturesAvailable,
            validateKey: { _, _ in }
        )
    }

    @Test func settingsAndCredentialsSurviveRelaunch() async throws {
        let defaults = try makeDefaults()
        let store = InMemoryCredentialStore()

        let first = makeManager(store, defaults: defaults)
        first.setTextModel("  first-model  ", for: .openAI)
        first.setTextModel("vendor/second-model", for: .openRouter)
        first.selectTextProvider(.openRouter)
        first.selectImageProvider(.replicate)
        try await first.saveCredential(" router-key-123456 \n", for: .openRouter)

        let second = makeManager(store, defaults: defaults)
        #expect(second.settings == first.settings)
        #expect(second.settings.textProvider == .openRouter)
        #expect(second.settings.imageProvider == .replicate)
        // Each provider keeps its own model ID.
        #expect(second.settings.model(for: TextProvider.openAI) == "first-model")
        #expect(second.settings.model(for: TextProvider.openRouter) == "vendor/second-model")

        try await second.refreshCredentialStatus()
        #expect(second.storedCredentials == [.openRouter])
        #expect(try await store.read(.openRouter) == "router-key-123456")
        let client = try await second.textClient()
        #expect(client.provider == .openRouter)
        #expect(client.model == "vendor/second-model")
        #expect(await client.manager.selectedService == .openRouter)
    }

    @Test func credentialsNeverReachUserDefaults() async throws {
        let defaults = try makeDefaults()
        let manager = makeManager(defaults: defaults)
        manager.setTextModel("some-model", for: .openAI)
        try await manager.saveCredential("openai-key-abcdefgh", for: .openAI)

        let data = try #require(defaults.data(forKey: AIConfigurationManager.settingsKey))
        #expect(!String(decoding: data, as: UTF8.self).contains("openai-key-abcdefgh"))
    }

    @Test func missingKeyAndModelAreActionable() async throws {
        let manager = makeManager(defaults: try makeDefaults())

        await #expect(throws: AIConfigurationError.missingCredential(.openAI)) {
            _ = try await manager.textClient()
        }
        try await manager.saveCredential("openai-key-abcdefgh", for: .openAI)
        await #expect(throws: AIConfigurationError.missingModel(.openAI)) {
            _ = try await manager.textClient()
        }
        manager.setTextModel("some-model", for: .openAI)
        #expect(try await manager.textClient().model == "some-model")

        try await manager.removeCredential(for: .openAI)
        #expect(manager.storedCredentials.isEmpty)
        await #expect(throws: AIConfigurationError.missingCredential(.openAI)) {
            _ = try await manager.textClient()
        }
        await #expect(throws: AIConfigurationError.emptyCredential) {
            try await manager.saveCredential("   ", for: .openAI)
        }
    }

    @Test func keysAreCheckedBeforeTheyAreSaved() async throws {
        let store = InMemoryCredentialStore()
        let checked = OSAllocatedUnfairLock(initialState: [String]())
        let manager = AIConfigurationManager(
            credentials: store, defaults: try makeDefaults(), logger: LoggingManager(), fixturesAvailable: true,
            validateKey: { kind, key in
                checked.withLock { $0.append("\(kind.rawValue):\(key)") }
                switch key {
                case "rejected-key-1234":
                    throw LLMError.http(status: 401, message: "bad key", code: nil, retryAfter: nil)
                case "offline-key-12345":
                    throw URLError(.notConnectedToInternet)
                default:
                    break
                }
            }
        )

        await #expect(throws: AIConfigurationError.rejectedCredential(.openAI)) {
            try await manager.saveCredential("rejected-key-1234", for: .openAI)
        }
        // A key that could not be checked is not saved either, and the cause is kept.
        await #expect(throws: URLError.self) {
            try await manager.saveCredential("offline-key-12345", for: .openAI)
        }
        #expect(try await store.read(.openAI) == nil)
        #expect(manager.storedCredentials.isEmpty)

        try await manager.saveCredential("  working-key-1234 ", for: .replicate)
        #expect(try await store.read(.replicate) == "working-key-1234")
        #expect(checked.withLock { $0 } == [
            "openai:rejected-key-1234", "openai:offline-key-12345", "replicate:working-key-1234",
        ])
        // An empty key is refused without asking the provider.
        await #expect(throws: AIConfigurationError.emptyCredential) {
            try await manager.saveCredential(" ", for: .jev)
        }
        #expect(checked.withLock { $0 }.count == 3)

        let rejection = ErrorDescription.describe(AIConfigurationError.rejectedCredential(.openAI))
        #expect(rejection?.recovery == ErrorDescription.Recovery.none)
        #expect(rejection?.message.contains("wasn't saved") == true)
    }

    @Test func textAndImagesAreConfiguredIndependently() async throws {
        let manager = makeManager(defaults: try makeDefaults())
        let request = ImageGenerationRequest(prompt: "A ruined tower")

        await #expect(throws: AIConfigurationError.imagesDisabled) {
            _ = try await manager.generateImage(request)
        }
        manager.selectImageProvider(.replicate)
        await #expect(throws: AIConfigurationError.missingCredential(.replicate)) {
            _ = try await manager.generateImage(request)
        }
        // Images work while the narrator still has no key.
        manager.selectImageProvider(.fixture)
        #expect(try await !manager.generateImage(request).imageData.isEmpty)
        await #expect(throws: AIConfigurationError.missingCredential(.openAI)) {
            _ = try await manager.textClient()
        }
    }

    @Test func decisionsAreConfiguredIndependently() async throws {
        let defaults = try makeDefaults()
        let store = InMemoryCredentialStore()
        let manager = makeManager(store, defaults: defaults)

        await #expect(throws: AIConfigurationError.missingCredential(.openAI)) {
            _ = try await manager.decisionClient()
        }
        manager.selectDecisionProvider(.jev)
        await #expect(throws: AIConfigurationError.missingCredential(.jev)) {
            _ = try await manager.decisionClient()
        }
        try await manager.saveCredential("jev-key-abcdefgh", for: .jev)
        await #expect(throws: AIConfigurationError.missingDecisionModel(.jev)) {
            _ = try await manager.decisionClient()
        }
        manager.setDecisionModel("jev-model", for: .jev)
        manager.setDecisionModel("router/decision-model", for: .openRouter)
        manager.setTextModel("narrator-model", for: .openRouter)

        let client = try await manager.decisionClient()
        #expect(client.provider == .jev)
        #expect(client.model == "jev-model")
        #expect(await client.manager.selectedDecisionService == .jev)
        // Decisions work while the narrator still has no key.
        await #expect(throws: AIConfigurationError.missingCredential(.openAI)) {
            _ = try await manager.textClient()
        }

        // Decision models are kept apart from text models for the same provider.
        let relaunched = makeManager(store, defaults: defaults)
        #expect(relaunched.settings.decisionProvider == .jev)
        #expect(relaunched.settings.model(for: DecisionProvider.openRouter) == "router/decision-model")
        #expect(relaunched.settings.model(for: TextProvider.openRouter) == "narrator-model")
    }

    @Test func settingsFromAnOlderBuildStillLoad() throws {
        let defaults = try makeDefaults()
        defaults.set(Data(#"{"textProvider":"openrouter","textModels":{"openrouter":"m"}}"#.utf8),
                     forKey: AIConfigurationManager.settingsKey)
        let manager = makeManager(defaults: defaults)
        #expect(manager.settings.textProvider == .openRouter)
        #expect(manager.settings.decisionProvider == .openAI)
        #expect(manager.settings.imageProvider == .off)
    }

    @Test func fixturesAreDevelopmentOnly() async throws {
        let defaults = try makeDefaults()
        let development = makeManager(defaults: defaults)
        development.selectTextProvider(.fixture)
        development.selectImageProvider(.fixture)
        development.selectDecisionProvider(.fixture)
        #expect(try await development.decisionClient().model == FixtureDecisionService.defaultModel)
        let client = try await development.textClient()
        #expect(client.model == FixtureTextService.defaultModel)

        let release = makeManager(defaults: defaults, fixturesAvailable: false)
        #expect(release.settings.textProvider == .openAI)
        #expect(release.settings.imageProvider == .off)
        #expect(release.settings.decisionProvider == .openAI)
        #expect(!release.availableTextProviders.contains(.fixture))
        release.selectTextProvider(.fixture)
        #expect(release.settings.textProvider == .openAI)
    }

    @Test func launchArgumentForcesFixtures() async throws {
        let defaults = try makeDefaults()
        defaults.set(true, forKey: AIConfigurationManager.fixturesArgument)

        let manager = makeManager(defaults: defaults)
        #expect(manager.forcesFixtures)
        #expect(manager.settings.textProvider == .openAI)
        #expect(try await manager.textClient().provider == .fixture)
        #expect(!makeManager(defaults: defaults, fixturesAvailable: false).forcesFixtures)
    }

    @Test func keychainStoresRetrievesAndRemoves() async throws {
        let store = KeychainCredentialStore(service: "epoch.tests.\(UUID().uuidString)")
        #expect(try await store.read(.replicate) == nil)
        try await store.save("first-value", for: .replicate)
        try await store.save("second-value", for: .replicate)
        #expect(try await store.read(.replicate) == "second-value")
        #expect(try await store.read(.openAI) == nil)
        try await store.remove(.replicate)
        try await store.remove(.replicate)
        #expect(try await store.read(.replicate) == nil)
    }
}

private nonisolated final class StubCatalog: EpochModelCatalog, Sendable {
    struct Call: Equatable {
        let provider: String
        let key: String
        let purpose: LLMModelPurpose
    }

    private let recorded = OSAllocatedUnfairLock(initialState: [Call]())
    let models: [LLMModelInfo]
    let failure: (any Error)?

    init(models: [LLMModelInfo] = [], failure: (any Error)? = nil) {
        self.models = models
        self.failure = failure
    }

    var calls: [Call] { recorded.withLock { $0 } }

    func factory() -> AIConfigurationManager.CatalogFactory {
        { provider, key in BoundCatalog(stub: self, provider: String(describing: provider), key: key) }
    }

    private struct BoundCatalog: EpochModelCatalog {
        let stub: StubCatalog
        let provider: String
        let key: String

        func listModels(for purpose: LLMModelPurpose) async throws -> [LLMModelInfo] {
            stub.recorded.withLock { $0.append(Call(provider: provider, key: key, purpose: purpose)) }
            if let failure = stub.failure { throw failure }
            return stub.models
        }
    }

    func listModels(for purpose: LLMModelPurpose) async throws -> [LLMModelInfo] { models }
}

@MainActor
struct ModelCatalogTests {
    private let sample = [
        LLMModelInfo(
            id: "vendor/sonnet-large", name: "Sonnet Large", summary: "A capable storyteller.",
            contextLength: 200_000, pricing: LLMModelPricing(inputPerMillionTokens: 3, outputPerMillionTokens: 15)
        ),
        LLMModelInfo(id: "plain-model", owner: "openai", retirementDate: "2027-01-01"),
        LLMModelInfo(id: "~vendor/latest", name: "Vendor Latest", aliasTarget: "vendor/sonnet-large"),
    ]

    private func makeManager(_ stub: StubCatalog, keys: [CredentialKind: String]) throws -> AIConfigurationManager {
        let name = "epoch.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return AIConfigurationManager(
            credentials: InMemoryCredentialStore(keys), defaults: defaults, logger: LoggingManager(),
            fixturesAvailable: true, makeCatalog: stub.factory(), validateKey: { _, _ in }
        )
    }

    @Test func listsModelsForEachRolesProviderAndKey() async throws {
        let stub = StubCatalog(models: sample)
        let manager = try makeManager(stub, keys: [.openAI: "openai-key-12345", .jev: "jev-key-1234567"])
        manager.selectDecisionProvider(.jev)

        #expect(try await manager.availableModels(for: .narrator) == sample)
        #expect(try await manager.availableModels(for: .decisions) == sample)
        #expect(stub.calls == [
            .init(provider: "openAI", key: "openai-key-12345", purpose: .text),
            .init(provider: "jev", key: "jev-key-1234567", purpose: .decisions),
        ])

        // A second look uses this launch's list; refreshing or changing the key asks again.
        _ = try await manager.availableModels(for: .narrator)
        #expect(stub.calls.count == 2)
        _ = try await manager.availableModels(for: .narrator, refresh: true)
        #expect(stub.calls.count == 3)
        try await manager.saveCredential("openai-key-67890", for: .openAI)
        _ = try await manager.availableModels(for: .narrator)
        #expect(stub.calls.last == .init(provider: "openAI", key: "openai-key-67890", purpose: .text))
    }

    @Test func listingNeedsAKeyAndFixturesNeedNothing() async throws {
        let stub = StubCatalog(models: sample)
        let manager = try makeManager(stub, keys: [:])

        await #expect(throws: AIConfigurationError.missingCredential(.openAI)) {
            _ = try await manager.availableModels(for: .narrator)
        }
        manager.selectTextProvider(.fixture)
        manager.selectDecisionProvider(.fixture)
        #expect(try await manager.availableModels(for: .narrator).map(\.id) == [FixtureTextService.defaultModel])
        #expect(try await manager.availableModels(for: .decisions).map(\.id) == [FixtureDecisionService.defaultModel])
        #expect(stub.calls.isEmpty)
    }

    @Test func openRouterModelsLoadWithoutAKey() async throws {
        let stub = StubCatalog(models: sample)
        let manager = try makeManager(stub, keys: [:])
        manager.selectTextProvider(.openRouter)
        manager.selectDecisionProvider(.openRouter)

        #expect(try await manager.availableModels(for: .narrator) == sample)
        #expect(try await manager.availableModels(for: .decisions) == sample)
        #expect(stub.calls == [
            .init(provider: "openRouter", key: "", purpose: .text),
            .init(provider: "openRouter", key: "", purpose: .decisions),
        ])
        // Choosing a model does not need a key; narrating with it still does.
        manager.selectModel("vendor/sonnet-large", for: .narrator)
        await #expect(throws: AIConfigurationError.missingCredential(.openRouter)) {
            _ = try await manager.textClient()
        }
        // Once a key exists it is sent along.
        try await manager.saveCredential("router-key-12345", for: .openRouter)
        _ = try await manager.availableModels(for: .narrator)
        #expect(stub.calls.last == .init(provider: "openRouter", key: "router-key-12345", purpose: .text))
    }

    @Test func pickerLoadsSearchesAndSelects() async throws {
        let manager = try makeManager(StubCatalog(models: sample), keys: [.openAI: "openai-key-12345"])
        let picker = ModelPickerViewModel(
            role: .narrator, configuration: manager, errors: ErrorManager(logger: LoggingManager())
        )
        await picker.load()
        #expect(picker.state == .loaded)
        #expect(picker.results.count == 3)

        picker.query = "SONNET storyteller"
        #expect(picker.results.map(\.id) == ["vendor/sonnet-large"])
        // Matches IDs, owners, and alias targets too.
        picker.query = "openai"
        #expect(picker.results.map(\.id) == ["plain-model"])
        picker.query = "sonnet"
        #expect(picker.results.map(\.id) == ["vendor/sonnet-large", "~vendor/latest"])
        picker.query = "nothing-like-this"
        #expect(picker.results.isEmpty)

        picker.select(sample[1])
        #expect(manager.settings.model(for: TextProvider.openAI) == "plain-model")
        #expect(picker.selectedID == "plain-model")
        #expect(!picker.selectionIsUnlisted)
        manager.setTextModel("retired-model", for: .openAI)
        #expect(picker.selectionIsUnlisted)
    }

    @Test func pickerShowsFailuresInPlace() async throws {
        let errors = ErrorManager(logger: LoggingManager())
        let rejected = StubCatalog(failure: LLMError.http(status: 401, message: "bad key", code: nil, retryAfter: nil))
        let picker = ModelPickerViewModel(
            role: .narrator, configuration: try makeManager(rejected, keys: [.openAI: "openai-key-12345"]),
            errors: errors
        )
        await picker.load()
        guard case .failed(let failure) = picker.state else {
            Issue.record("Expected a failure state")
            return
        }
        #expect(failure.recovery == .openSettings)
        // Reported for logging, but not as a banner over the message already on screen.
        #expect(errors.latestError is LLMError)
        #expect(errors.banner == nil)

        let noKey = ModelPickerViewModel(
            role: .decisions, configuration: try makeManager(StubCatalog(), keys: [:]), errors: errors
        )
        await noKey.load()
        #expect(noKey.state == .failed(try #require(
            ErrorDescription.describe(AIConfigurationError.missingCredential(.openAI))
        )))
    }

    @Test func rowsShowOnlyWhatTheProviderReports() {
        #expect(ModelDetails.title(sample[0]) == "Sonnet Large")
        #expect(ModelDetails.identifier(sample[0]) == "vendor/sonnet-large")
        #expect(ModelDetails.facts(sample[0]) == "$3.00 in · $15.00 out per M tokens · 200K context")

        #expect(ModelDetails.title(sample[1]) == "plain-model")
        #expect(ModelDetails.identifier(sample[1]) == nil)
        #expect(ModelDetails.facts(sample[1]) == "openai")
        #expect(ModelDetails.facts(sample[2]) == "points to vendor/sonnet-large")
        #expect(ModelDetails.facts(LLMModelInfo(id: "bare")) == nil)

        #expect(ModelDetails.price(LLMModelPricing(inputPerMillionTokens: 0, outputPerMillionTokens: 0)) == "Free")
        #expect(ModelDetails.price(LLMModelPricing(inputPerMillionTokens: 0.042, outputPerMillionTokens: nil))
            == "$0.042 in per M tokens")
        #expect(ModelDetails.dollars(0.0025) == "$0.0025")
        #expect(ModelDetails.dollars(0.5) == "$0.50")
        #expect(ModelDetails.tokens(8192) == "8K")
        #expect(ModelDetails.tokens(1_048_576) == "1M")
        #expect(ModelDetails.tokens(512) == "512")

        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0) ?? utc.timeZone
        let dated = LLMModelInfo(id: "dated", released: Date(timeIntervalSince1970: 1_786_935_002))
        #expect(ModelDetails.facts(dated, calendar: utc)?.contains("2026") == true)
    }
}

@MainActor
struct FixtureTests {
    private func request(_ turns: String...) -> LLMRequest {
        LLMRequest(model: FixtureTextService.defaultModel, input: turns.map { .message(.user, $0) })
    }

    @Test func textIsDeterministic() async throws {
        let service = FixtureTextService(chunkDelay: .zero)
        let first = try await service.send(request("I open the door."))
        let second = try await service.send(request("I open the door."))
        #expect(first == second)
        #expect(first.isComplete)
        #expect(first.toolCalls.isEmpty)
        #expect(FixtureTextService.passages.contains(first.text))
        #expect(first.id != (try await service.send(request("I open the door.", "I wait."))).id)
    }

    @Test func streamMatchesSend() async throws {
        let service = FixtureTextService(chunkDelay: .zero)
        let expected = try await service.send(request("I light the lantern."))
        var streamed = ""
        var final: LLMResponse?
        for try await event in service.stream(request("I light the lantern.")) {
            switch event {
            case .textDelta(let delta): streamed += delta
            case .response(let response): final = response
            default: break
            }
        }
        #expect(streamed == expected.text)
        #expect(final == expected)
    }

    @Test func decisionsAreDeterministic() async throws {
        let service = FixtureDecisionService()
        let request = DecisionRequest(
            model: FixtureDecisionService.defaultModel,
            state: .json(.object(["scene": .string("inn"), "weapon": .string("dagger")])),
            questions: [
                .predicate("is_hostile", "Is the player hostile?"),
                .choice("intent", "What is the player doing?", options: ["fight", "intimidate", "trade"]),
                .score("tension", "How tense is the scene?", levels: ["calm", "uneasy", "violent"]),
            ]
        )
        let first = try await service.decide(request)
        #expect(first == (try await service.decide(request)))
        #expect(first.answers.count == 3)
        #expect([0.2, 0.8].contains(try #require(first["is_hostile"]?.probability)))

        let choice = try #require(first["intent"]?.choice)
        #expect(["fight", "intimidate", "trade"].contains(choice.choice))
        #expect(choice.probabilities[choice.choice] == 0.8)
        #expect(abs(choice.probabilities.values.reduce(0, +) - 1) < 1e-9)

        let score = try #require(first["tension"]?.score)
        #expect(score.levels.map(\.label) == ["calm", "uneasy", "violent"])
        #expect((0...2).contains(score.score))
    }

    @Test func imagesAreDeterministic() async throws {
        let service = FixtureImageService()
        let request = ImageGenerationRequest(prompt: "A moonlit tower", aspectRatio: .landscape)
        let first = try await service.generateImage(request)
        let second = try await service.generateImage(request)
        #expect(first == second)
        // PNG signature.
        #expect(first.imageData.prefix(4) == Data([0x89, 0x50, 0x4E, 0x47]))
        #expect(first.outputFormat == .png)

        let webp = try await service.generateImage(ImageGenerationRequest(prompt: "A tower", outputFormat: .webp))
        #expect(webp.outputFormat == .png)
        await #expect(throws: LLMError.self) {
            _ = try await service.generateImage(ImageGenerationRequest(prompt: "  "))
        }
    }
}
