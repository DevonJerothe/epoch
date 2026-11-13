import Foundation
import os
import Testing
@testable import EpochLLM

/// Replies in order to the requests of one session, and records what was asked.
private final class CatalogFixtureProtocol: URLProtocol, @unchecked Sendable {
    static let header = "X-Catalog-Fixture"

    struct Script {
        var replies: [(status: Int, body: String)]
        var requests: [URLRequest] = []
    }

    static let scripts = OSAllocatedUnfairLock(initialState: [String: Script]())

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let request = self.request
        let reply = request.value(forHTTPHeaderField: Self.header).flatMap { id in
            Self.scripts.withLock { scripts -> (status: Int, body: String)? in
                guard var script = scripts[id], !script.replies.isEmpty else { return nil }
                let reply = script.replies.removeFirst()
                script.requests.append(request)
                scripts[id] = script
                return reply
            }
        }
        guard let url = request.url, let reply else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let response = HTTPURLResponse(
            url: url, statusCode: reply.status, httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(reply.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

private struct CatalogFixture {
    let id = UUID().uuidString
    let session: URLSession

    init(_ bodies: String..., status: Int = 200) {
        let replies = bodies.map { (status: status, body: $0) }
        let id = self.id
        CatalogFixtureProtocol.scripts.withLock { $0[id] = .init(replies: replies) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CatalogFixtureProtocol.self]
        configuration.httpAdditionalHeaders = [CatalogFixtureProtocol.header: id]
        session = URLSession(configuration: configuration)
    }

    var requests: [URLRequest] {
        CatalogFixtureProtocol.scripts.withLock { $0[id]?.requests ?? [] }
    }
}

private func query(_ request: URLRequest) -> [String: String] {
    let items = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: true) }?.queryItems ?? []
    return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
}

private let openAIModels = #"""
{"object":"list","data":[
 {"id":"older-model","object":"model","created":1686935002,"owned_by":"openai","shutdown_date":"2026-10-23"},
 {"id":"gpt-6-luna","object":"model","created":1786935002,"owned_by":"openai","shutdown_date":null},
 {"id":"newer-model","object":"model","created":1796935002,"owned_by":"organization-owner"},
 {"id":"text-embedding-9-large","object":"model","created":1796935003,"owned_by":"openai"},
 {"id":"gpt-9-Audio-preview","object":"model","created":1796935004,"owned_by":"openai"},
 {"id":"gpt-image-3","object":"model","created":1796935005,"owned_by":"openai"},
 {"id":"omni-moderation-latest","object":"model","created":1796935006,"owned_by":"openai"}
]}
"""#

@Test func openAIListsTextModelsNewestFirst() async throws {
    let fixture = CatalogFixture(openAIModels)
    let models = try await ModelCatalogService.openAI(apiKey: "test-key", session: fixture.session)
        .listModels(for: .text)

    #expect(models.map(\.id) == ["newer-model", "gpt-6-luna", "older-model"])
    #expect(models[2].owner == "openai")
    #expect(models[2].retirementDate == "2026-10-23")
    #expect(models[2].released == Date(timeIntervalSince1970: 1_686_935_002))
    for id in [
        "tts-2", "whisper-2", "gpt-9-transcribe", "gpt-9-realtime", "dall-e-4", "sora-3",
        "gpt-5-search-api", "gpt-4o-mini-search-preview",
    ] {
        #expect(!ModelCatalogService.isOpenAITextModel(id), "\(id)")
    }
    #expect(ModelCatalogService.isOpenAITextModel("gpt-9-mini"))
    // OpenAI reports none of these.
    #expect(models.allSatisfy { $0.name == nil && $0.pricing == nil && $0.contextLength == nil })

    let request = try #require(fixture.requests.first)
    #expect(request.url?.absoluteString == "https://api.openai.com/v1/models")
    #expect(request.httpMethod == "GET")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
}

@Test func openAIDecisionsKeepsDocumentedModels() async throws {
    let fixture = CatalogFixture(openAIModels)
    let models = try await ModelCatalogService.openAI(apiKey: "test-key", session: fixture.session)
        .listModels(for: .decisions)
    #expect(models.map(\.id) == ["gpt-6-luna"])
}

private let openRouterFirstPage = #"""
{"data":[
 {"id":"openai/gpt-4","canonical_slug":"openai/gpt-4","name":"GPT-4","created":1692901234,
  "description":"A large multimodal model.","context_length":8192,"expiration_date":null,
  "pricing":{"prompt":"0.00003","completion":"0.00006","image":"0","request":"0"},
  "architecture":{"modality":"text->text"},"endpoints":["/api/v1/responses"]},
 {"id":"~vendor/model-latest","name":"Vendor Latest","created":1700000000,"context_length":null,
  "pricing":{"prompt":"0","completion":"0"},"alias_target":{"slug":"vendor/model-2","name":"Model 2"}}
],"total_count":3,"links":{"next":"/api/v1/models?offset=500&limit=500&endpoints=%2Fapi%2Fv1%2Fresponses"}}
"""#

private let openRouterLastPage = #"""
{"data":[
 {"id":"vendor/unpriced","name":"Unpriced","created":1700000001,"pricing":{"prompt":"n/a","completion":"-1"}},
 {"id":"openai/gpt-4","name":"Duplicate","created":1,"pricing":{"prompt":"1","completion":"1"}}
],"total_count":3,"links":{"next":null}}
"""#

@Test func openRouterFollowsPagesAndReadsPricing() async throws {
    let fixture = CatalogFixture(openRouterFirstPage, openRouterLastPage)
    let models = try await ModelCatalogService
        .openRouter(apiKey: "router-key", appName: "Epoch", session: fixture.session)
        .listModels(for: .text)

    #expect(models.map(\.id) == ["openai/gpt-4", "~vendor/model-latest", "vendor/unpriced"])
    let first = models[0]
    #expect(first.name == "GPT-4")
    #expect(first.summary == "A large multimodal model.")
    #expect(first.contextLength == 8192)
    #expect(first.pricing == LLMModelPricing(inputPerMillionTokens: 30, outputPerMillionTokens: 60))
    #expect(models[1].aliasTarget == "vendor/model-2")
    #expect(models[1].pricing == LLMModelPricing(inputPerMillionTokens: 0, outputPerMillionTokens: 0))
    #expect(models[2].pricing == nil)

    let requests = fixture.requests
    #expect(requests.count == 2)
    #expect(requests[0].url?.host == "openrouter.ai")
    #expect(requests[0].url?.path == "/api/v1/models")
    #expect(query(requests[0]) == [
        "limit": "500", "endpoints": "/api/v1/responses", "output_modalities": "text",
    ])
    #expect(requests[0].value(forHTTPHeaderField: "Authorization") == "Bearer router-key")
    #expect(requests[0].value(forHTTPHeaderField: "X-Title") == "Epoch")
    #expect(query(requests[1])["offset"] == "500")
    #expect(requests[1].url?.host == "openrouter.ai")
}

@Test func openRouterDecisionsAsksForDecisionModels() async throws {
    let fixture = CatalogFixture(#"{"data":[{"id":"typesafe/jev-1.14","name":"Jev 1.14"}],"links":{"next":null}}"#)
    let models = try await ModelCatalogService.openRouter(apiKey: "router-key", session: fixture.session)
        .listModels(for: .decisions)
    #expect(models.map(\.id) == ["typesafe/jev-1.14"])
    #expect(query(try #require(fixture.requests.first)) == [
        "limit": "500", "endpoints": "/api/alpha/decisions", "output_modalities": "decisions",
    ])
}

@Test func openRouterRejectsNextLinksToOtherHosts() async throws {
    let fixture = CatalogFixture(
        #"{"data":[{"id":"a/b"}],"links":{"next":"https://example.com/api/v1/models"}}"#, "{}"
    )
    await #expect(throws: LLMError.self) {
        _ = try await ModelCatalogService.openRouter(apiKey: "router-key", session: fixture.session)
            .listModels(for: .text)
    }
    // The key is never sent to the other host.
    #expect(fixture.requests.count == 1)
}

@Test func jevListsAliasesForDecisionsOnly() async throws {
    let fixture = CatalogFixture(
        #"{"models":[{"name":"jev-latest","description":"General-purpose system one model.","release_date":"2026-09-15"}]}"#
    )
    let service = ModelCatalogService.jev(apiKey: "jev-key", session: fixture.session)
    let models = try await service.listModels(for: .decisions)

    #expect(models.map(\.id) == ["jev-latest"])
    #expect(models[0].summary == "General-purpose system one model.")
    #expect(models[0].released == ModelCatalogService.date(fromDay: "2026-09-15"))
    #expect(models[0].released != nil)
    let request = try #require(fixture.requests.first)
    #expect(request.url?.absoluteString == "https://api.typesafe.ai/v1/models")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer jev-key")

    await #expect(throws: LLMError.self) { _ = try await service.listModels(for: .text) }
    #expect(fixture.requests.count == 1)
}

@Test func modelListFailuresAreNormalized() async throws {
    let unauthorized = CatalogFixture(#"{"error":{"message":"Incorrect API key","code":"invalid_api_key"}}"#, status: 401)
    do {
        _ = try await ModelCatalogService.openAI(apiKey: "bad", session: unauthorized.session).listModels(for: .text)
        Issue.record("Expected an HTTP error")
    } catch LLMError.http(let status, let message, let code, _) {
        #expect(status == 401)
        #expect(message == "Incorrect API key")
        #expect(code == "invalid_api_key")
    }

    let malformed = CatalogFixture(#"{"unexpected":true}"#)
    await #expect(throws: LLMError.self) {
        _ = try await ModelCatalogService.openAI(apiKey: "key", session: malformed.session).listModels(for: .text)
    }
    // A missing key fails before any request.
    let unused = CatalogFixture("{}")
    await #expect(throws: LLMError.self) {
        _ = try await ModelCatalogService.jev(apiKey: "  ", session: unused.session).listModels(for: .decisions)
    }
    #expect(unused.requests.isEmpty)
}

@Test func openRouterListsModelsWithoutAKey() async throws {
    let fixture = CatalogFixture(#"{"data":[{"id":"a/b","name":"B"}],"links":{"next":null}}"#)
    let models = try await ModelCatalogService.openRouter(session: fixture.session).listModels(for: .text)
    #expect(models.map(\.id) == ["a/b"])
    #expect(try #require(fixture.requests.first).value(forHTTPHeaderField: "Authorization") == nil)

    // The other providers still refuse before any request.
    let unused = CatalogFixture("{}")
    await #expect(throws: LLMError.self) {
        _ = try await ModelCatalogService(provider: .openAI, apiKey: nil, session: unused.session)
            .listModels(for: .text)
    }
    #expect(unused.requests.isEmpty)
}

@Test(arguments: [
    (APIKeyValidator.Provider.openAI, "https://api.openai.com/v1/models"),
    (.openRouter, "https://openrouter.ai/api/v1/key"),
    (.jev, "https://api.typesafe.ai/v1/models"),
    (.replicate, "https://api.replicate.com/v1/account"),
])
func keyValidationAsksTheRightEndpoint(provider: APIKeyValidator.Provider, url: String) async throws {
    let fixture = CatalogFixture(#"{"data":{"label":"sk-or-v1-au7...890"}}"#)
    try await APIKeyValidator(provider: provider, session: fixture.session).validate("  good-key\n")

    let request = try #require(fixture.requests.first)
    #expect(fixture.requests.count == 1)
    #expect(request.url?.absoluteString == url)
    #expect(request.httpMethod == "GET")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer good-key")
}

@Test func keyValidationSeparatesRejectedFromUnchecked() async throws {
    let rejected = CatalogFixture(#"{"error":{"code":401,"message":"Missing Authentication header"}}"#, status: 401)
    do {
        try await APIKeyValidator(provider: .openRouter, session: rejected.session).validate("bad-key")
        Issue.record("Expected the key to be rejected")
    } catch let error as LLMError {
        #expect(error.isRejectedCredential)
    }

    // Replicate reports errors as {"detail": ...}.
    let throttled = CatalogFixture(#"{"detail":"Request was throttled."}"#, status: 429)
    do {
        try await APIKeyValidator(provider: .replicate, session: throttled.session).validate("some-key")
        Issue.record("Expected a failure")
    } catch let error as LLMError {
        #expect(!error.isRejectedCredential)
        #expect(error.isRetryable)
        #expect(error.localizedDescription.contains("Request was throttled."))
    }

    let unused = CatalogFixture("{}")
    await #expect(throws: LLMError.self) {
        try await APIKeyValidator(provider: .openAI, session: unused.session).validate("   ")
    }
    #expect(unused.requests.isEmpty)
}
