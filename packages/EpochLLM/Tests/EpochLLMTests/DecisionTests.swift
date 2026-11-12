import Foundation
import os
import Testing
@testable import EpochLLM

/// Replies are keyed by the request's `X-Decision-Fixture` header.
private final class DecisionFixtureProtocol: URLProtocol, @unchecked Sendable {
    static let header = "X-Decision-Fixture"
    static let fixtures = OSAllocatedUnfairLock(initialState: [String: (Int, String, [String: String])]())

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let url = request.url, let id = request.value(forHTTPHeaderField: Self.header),
              let (status, body, extra) = Self.fixtures.withLock({ $0[id] }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        var headers = ["Content-Type": "application/json"]
        headers.merge(extra) { $1 }
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

private func fixtureSession(status: Int = 200, body: String, headers: [String: String] = [:]) -> URLSession {
    let id = UUID().uuidString
    DecisionFixtureProtocol.fixtures.withLock { $0[id] = (status, body, headers) }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [DecisionFixtureProtocol.self]
    configuration.httpAdditionalHeaders = [DecisionFixtureProtocol.header: id]
    return URLSession(configuration: configuration)
}

private func body(_ request: URLRequest) throws -> [String: JSONValue] {
    try JSONDecoder().decode([String: JSONValue].self, from: try #require(request.httpBody))
}

private let questions: [DecisionQuestion] = [
    .predicate("hostile", "Is the innkeeper hostile?", whenTrue: "Threats or drawn weapons", whenFalse: "Polite"),
    .choice("intent", "What does the player intend?", options: ["fight", DecisionOption("talk", description: "Negotiate"), "flee"]),
    .score("tension", "How tense is the scene?", levels: ["calm", DecisionLevel("uneasy", description: "Some friction"), "violent"]),
]

private func request(model: String) -> DecisionRequest {
    DecisionRequest(model: model, state: .text("The innkeeper glares."), questions: questions)
}

@Test func openAIDecisionWireContract() throws {
    let wire = try DecisionService.openAI(apiKey: "test-key").makeRequest(request(model: "gpt-6-luna"))
    #expect(wire.url?.absoluteString == "https://api.openai.com/v1/decisions")
    #expect(wire.httpMethod == "POST")
    #expect(wire.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
    let json = try body(wire)
    #expect(json["model"] == .string("gpt-6-luna"))
    #expect(json["input"] == .string("The innkeeper glares."))
    let list = try #require(json["questions"]?.array).compactMap(\.object)
    #expect(list.map { $0["name"] } == [.string("hostile"), .string("intent"), .string("tension")])
    #expect(list[0]["type"] == .string("predicate"))
    let instructions = try #require(list[0]["instructions"]?.string)
    #expect(instructions.contains("Answer true when: Threats or drawn weapons"))
    #expect(list[0]["criteria"] == nil)
    #expect(list[1]["choices"] == .array([
        .object(["value": .string("fight")]),
        .object(["value": .string("talk"), "description": .string("Negotiate")]),
        .object(["value": .string("flee")]),
    ]))
    #expect(list[2]["levels"]?.array?[1] == .object(["label": .string("uneasy"), "description": .string("Some friction")]))
}

@Test func systemOneDecisionWireContract() throws {
    for (service, endpoint) in [
        (DecisionService.openRouter(apiKey: "test-key", appName: "Epoch"), "https://openrouter.ai/api/alpha/decisions"),
        (DecisionService.jev(apiKey: "test-key"), "https://api.typesafe.ai/v1/systemone"),
    ] {
        var decision = request(model: "jev-latest")
        decision.state = .json(.object(["hp": .integer(4)]))
        let wire = try service.makeRequest(decision)
        #expect(wire.url?.absoluteString == endpoint)
        let json = try body(wire)
        #expect(json["state"] == .object(["hp": .integer(4)]))
        let map = try #require(json["questions"]?.object)
        #expect(map["hostile"] == .object([
            "type": .string("noul"), "instructions": .string("Is the innkeeper hostile?"),
            "criteria": .object(["true": .string("Threats or drawn weapons"), "false": .string("Polite")]),
        ]))
        #expect(map["intent"]?.object?["criteria"] == .object([
            "fight": .null, "talk": .string("Negotiate"), "flee": .null,
        ]))
        #expect(map["tension"]?.object?["criteria"] == .array([
            .string("calm"), .string("uneasy: Some friction"), .string("violent"),
        ]))
    }
    let router = try DecisionService.openRouter(apiKey: "k", appName: "Epoch").makeRequest(request(model: "m"))
    #expect(router.value(forHTTPHeaderField: "X-Title") == "Epoch")
}

@Test func openAIStateJSONIsSentAsText() throws {
    var decision = request(model: "gpt-6-luna")
    decision.state = .json(.object(["b": .integer(2), "a": .integer(1)]))
    let json = try body(DecisionService.openAI(apiKey: "k").makeRequest(decision))
    #expect(json["input"] == .string(#"{"a":1,"b":2}"#))
}

@Test func openAIDecisionResponseParsesInQuestionOrder() async throws {
    let session = fixtureSession(body: #"""
    {"model":"gpt-6-luna","answers":[
      {"type":"predicate","name":"hostile","probability":0.9},
      {"type":"choice","name":"intent","choice":"talk","confidence":0.7,
       "probabilities":[{"value":"fight","probability":0.2},{"value":"talk","probability":0.7},{"value":"flee","probability":0.1}]},
      {"type":"refusal","name":"tension"}
    ],"usage":{"input_tokens":42,"input_tokens_details":{"cached_tokens":5,"cache_write_tokens":0},
      "output_tokens":0,"output_tokens_details":{"reasoning_tokens":0},"total_tokens":42}}
    """#)
    defer { session.invalidateAndCancel() }
    let response = try await DecisionService.openAI(apiKey: "k", session: session).decide(request(model: "gpt-6-luna"))
    #expect(response.model == "gpt-6-luna")
    #expect(response.id == nil)
    #expect(response["hostile"] == .predicate(probability: 0.9, confidence: nil))
    #expect(response["intent"]?.choice?.choice == "talk")
    #expect(response["intent"]?.choice?.probabilities == ["fight": 0.2, "talk": 0.7, "flee": 0.1])
    #expect(response["tension"]?.isRefusal == true)
    #expect(response.usage == DecisionUsage(inputTokens: 42, outputTokens: 0, totalTokens: 42, cachedInputTokens: 5))
}

@Test func openAIScoreMapsProbabilitiesToLevels() async throws {
    let session = fixtureSession(body: #"""
    {"model":"gpt-6-luna","answers":[{"type":"score","name":"tension","score":1.6,"confidence":0.6,
      "probabilities":[{"label":"calm","probability":0.0,"value":0},{"label":"uneasy","probability":0.4,"value":1},
                       {"label":"violent","probability":0.6,"value":2}]}],
     "usage":{"input_tokens":1,"output_tokens":0,"total_tokens":1}}
    """#)
    defer { session.invalidateAndCancel() }
    let decision = DecisionRequest(model: "gpt-6-luna", state: .text("x"), questions: [questions[2]])
    let score = try #require(try await DecisionService.openAI(apiKey: "k", session: session).decide(decision)["tension"]?.score)
    #expect(score.score == 1.6)
    #expect(score.levels.map(\.probability) == [0.0, 0.4, 0.6])
    #expect(score.mostLikelyLevel?.label == "violent")
}

@Test func openRouterDecisionResponseKeepsMetadataAndDistributions() async throws {
    let session = fixtureSession(body: #"""
    {"id":"gen-dec-1","model":"typesafe/jev-1.13-20260917","provider":"TypeSafe","answers":{
      "hostile":{"type":"noul","noul":0.96},
      "intent":{"type":"choice","choice":"flee","confidence":0.75,"probabilities":{"fight":0,"talk":0.25,"flee":0.75}},
      "tension":{"type":"score","score":1.99,"confidence":0.99,"probabilities":{"0":0,"1":0.01,"2":0.99},
                 "legend":{"0":"calm","1":"uneasy: Some friction","2":"violent"}}},
     "usage":{"input_tokens":476,"output_tokens":70,"cost":0.000019992,"input_tokens_details":{"cached_tokens":0}}}
    """#)
    defer { session.invalidateAndCancel() }
    let response = try await DecisionService.openRouter(apiKey: "k", session: session).decide(request(model: "typesafe/jev-1.13"))
    #expect(response.id == "gen-dec-1")
    #expect(response.provider == "TypeSafe")
    #expect(response.model == "typesafe/jev-1.13-20260917")
    #expect(response["hostile"]?.probability == 0.96)
    #expect(response["intent"]?.choice == DecisionChoiceAnswer(
        choice: "flee", confidence: 0.75, probabilities: ["fight": 0, "talk": 0.25, "flee": 0.75]
    ))
    let score = try #require(response["tension"]?.score)
    #expect(score.levels.map(\.label) == ["calm", "uneasy", "violent"])
    #expect(score.levels.map(\.probability) == [0, 0.01, 0.99])
    #expect(response.usage?.cost == 0.000019992)
    #expect(response.usage?.totalTokens == nil)
    #expect(response.raw.object?["answers"]?.object?["tension"]?.object?["legend"] != nil)
}

@Test(arguments: [
    // Missing answer for a requested question.
    #"{"model":"m","answers":{"hostile":{"type":"noul","noul":0.5}},"usage":{"input_tokens":1,"output_tokens":1}}"#,
    // Wrong answer type for the question.
    #"{"model":"m","answers":{"hostile":{"type":"choice","choice":"x"},"intent":{"type":"refusal"},"tension":{"type":"refusal"}}}"#,
    // Choice outside the requested options.
    #"{"model":"m","answers":{"hostile":{"type":"refusal"},"intent":{"type":"choice","choice":"dance"},"tension":{"type":"refusal"}}}"#,
    // Probability outside 0...1.
    #"{"model":"m","answers":{"hostile":{"type":"noul","noul":1.5},"intent":{"type":"refusal"},"tension":{"type":"refusal"}}}"#,
    // Score beyond the last level.
    #"{"model":"m","answers":{"hostile":{"type":"refusal"},"intent":{"type":"refusal"},"tension":{"type":"score","score":3}}}"#,
    // Body that is not JSON at all.
    "<html>Bad gateway</html>",
    // Token counts that cannot be represented as Int, or are fractional or negative.
    #"{"model":"m","answers":{"hostile":{"type":"refusal"},"intent":{"type":"refusal"},"tension":{"type":"refusal"}},"usage":{"input_tokens":1e300,"output_tokens":1}}"#,
    #"{"model":"m","answers":{"hostile":{"type":"refusal"},"intent":{"type":"refusal"},"tension":{"type":"refusal"}},"usage":{"input_tokens":1,"output_tokens":1.5}}"#,
    #"{"model":"m","answers":{"hostile":{"type":"refusal"},"intent":{"type":"refusal"},"tension":{"type":"refusal"}},"usage":{"input_tokens":1,"output_tokens":1,"total_tokens":-2}}"#,
])
func malformedDecisionResponsesThrow(json: String) async throws {
    let session = fixtureSession(body: json)
    defer { session.invalidateAndCancel() }
    await #expect(throws: LLMError.self) {
        _ = try await DecisionService.jev(apiKey: "k", session: session).decide(request(model: "jev-latest"))
    }
}

@Test func openAIScoreIgnoresUnrepresentableFallbackValue() async throws {
    let json = #"{"model":"m","answers":[{"type":"refusal"},{"type":"refusal"},{"type":"score","score":1,"probabilities":[{"label":"unknown","value":1e300,"probability":0.5},{"label":"other","value":1.5,"probability":0.2},{"label":"renamed","value":2,"probability":0.3}]}]}"#
    let session = fixtureSession(body: json)
    defer { session.invalidateAndCancel() }
    let response = try await DecisionService.openAI(apiKey: "k", session: session).decide(request(model: "gpt-6-luna"))
    #expect(response["tension"]?.score?.levels.map(\.probability) == [nil, nil, 0.3])
}

@Test func openAIAnswerNameMismatchThrows() async throws {
    let session = fixtureSession(body: #"{"model":"m","answers":[{"type":"refusal","name":"other"},{"type":"refusal"},{"type":"refusal"}]}"#)
    defer { session.invalidateAndCancel() }
    await #expect(throws: LLMError.self) {
        _ = try await DecisionService.openAI(apiKey: "k", session: session).decide(request(model: "gpt-6-luna"))
    }
}

@Test func decisionHTTPErrorsAreNormalizedAndClassified() async throws {
    let cases: [(DecisionService, Int, String, String, String?, Bool)] = [
        (.openAI(apiKey: "k"), 400, #"{"error":{"message":"Bad question","code":"invalid_request"}}"#,
         "Bad question", "invalid_request", false),
        (.openRouter(apiKey: "k"), 402, #"{"error":{"code":402,"message":"Insufficient credits"}}"#,
         "Insufficient credits", "402", false),
        (.jev(apiKey: "k"), 422, #"{"detail":[{"loc":["body","state"],"msg":"Field required","type":"missing"}]}"#,
         "body.state: Field required", "missing", false),
        (.jev(apiKey: "k"), 529, #"{"detail":"Overloaded"}"#, "Overloaded", nil, true),
        // Non-JSON bodies fall back to Foundation's status text, which varies by OS.
        (.openRouter(apiKey: "k"), 429, "not json", HTTPURLResponse.localizedString(forStatusCode: 429), nil, true),
    ]
    for (template, status, json, message, code, retryable) in cases {
        let session = fixtureSession(status: status, body: json, headers: ["Retry-After": "3"])
        defer { session.invalidateAndCancel() }
        let service = DecisionService(
            id: template.id, endpoint: template.endpoint, format: template.format, apiKey: "k", session: session
        )
        do {
            _ = try await service.decide(request(model: "m"))
            Issue.record("Expected HTTP \(status) to throw")
        } catch let error as LLMError {
            guard case .http(let s, let m, let c, let retryAfter) = error else {
                Issue.record("Unexpected error \(error)")
                continue
            }
            #expect(s == status)
            #expect(m == message)
            #expect(c == code)
            #expect(retryAfter == "3")
            #expect(error.isRetryable == retryable)
        }
    }
}

@Test(arguments: [
    DecisionRequest(model: " ", state: .text("x"), questions: [questions[0]]),
    DecisionRequest(model: "m", state: .text("x"), questions: []),
    DecisionRequest(model: "m", state: .text("x"), questions: [questions[0], questions[0]]),
    DecisionRequest(model: "m", state: .text("x"), questions: [.choice("c", "Pick", options: ["only"])]),
    DecisionRequest(model: "m", state: .text("x"), questions: [.choice("c", "Pick", options: ["a", "a"])]),
    DecisionRequest(model: "m", state: .text("x"), questions: [.score("s", "Rate", levels: ["one"])]),
    DecisionRequest(model: "m", state: .text("x"), questions: [.score("s", "Rate", levels: ["a", "b", "a"])]),
])
func invalidDecisionRequestsFailBeforeNetwork(decision: DecisionRequest) {
    for service in [DecisionService.openAI(apiKey: "k"), .openRouter(apiKey: "k"), .jev(apiKey: "k")] {
        #expect(throws: LLMError.self) { try service.makeRequest(decision) }
    }
    #expect(throws: LLMError.self) { try DecisionService.jev(apiKey: " ").makeRequest(request(model: "m")) }
}

private struct StubDecisionService: EpochDecisionService {
    let id: LLMServiceID
    func decide(_ request: DecisionRequest) async throws -> DecisionResponse {
        DecisionResponse(model: id.rawValue, answers: [:])
    }
}

private struct StubTextService: EpochLLMService {
    let id = LLMServiceID.openAI
    func send(_ request: LLMRequest) async throws -> LLMResponse {
        LLMResponse(id: "r", model: "m", status: "completed", output: [])
    }
    func stream(_ request: LLMRequest) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}

@Test func managerSelectsDecisionServices() async throws {
    let manager = EpochAIManager(service: StubTextService())
    let empty = DecisionRequest(model: "m", state: .text("x"), questions: [questions[0]])
    await #expect(throws: LLMError.self) { _ = try await manager.decide(empty) }

    await manager.registerDecisionService(StubDecisionService(id: .jev))
    await manager.registerDecisionService(StubDecisionService(id: .openRouter))
    #expect(await manager.selectedDecisionService == .jev)
    #expect(try await manager.decide(empty).model == "jev")

    try await manager.selectDecisionService(.openRouter)
    #expect(try await manager.decide(empty).model == "openrouter")
    #expect(try await manager.decide(empty, using: .jev).model == "jev")
    #expect(await manager.selectedService == .openAI)
    await #expect(throws: LLMError.self) { try await manager.selectDecisionService(.openAI) }
}
