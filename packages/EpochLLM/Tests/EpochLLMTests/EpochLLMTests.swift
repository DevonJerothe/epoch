import Foundation
import Testing
@testable import EpochLLM

private let mixedResponse = #"""
{
  "id":"resp_1", "model":"test-model", "status":"completed",
  "output":[
    {"type":"reasoning","id":"rs_1","summary":[],"encrypted_content":"opaque","future_field":{"x":1}},
    {"type":"message","id":"msg_1","role":"assistant","status":"completed","content":[
      {"type":"output_text","text":"The door opens. ","annotations":[]},
      {"type":"refusal","refusal":"Cannot do that."},
      {"type":"output_text","text":"Roll initiative.","annotations":[]}
    ]},
    {"type":"function_call","id":"fc_1","call_id":"call_1","name":"roll_dice","arguments":"{\"sides\":20}","status":"completed"},
    {"type":"function_call","id":"fc_2","call_id":"call_2","name":"inventory","arguments":"{}","status":"completed"}
  ],
  "usage":{"input_tokens":15,"output_tokens":10,"total_tokens":25,"output_tokens_details":{"reasoning_tokens":3}},
  "error":null,"incomplete_details":null
}
"""#

private func decodeResponse(_ json: String = mixedResponse) throws -> LLMResponse {
    try JSONDecoder().decode(LLMResponse.self, from: Data(json.utf8))
}

private func requestBody(_ request: URLRequest) throws -> [String: JSONValue] {
    let data: Data
    if let body = request.httpBody { data = body }
    else if let stream = request.httpBodyStream {
        stream.open()
        defer { stream.close() }
        var bytes = [UInt8](repeating: 0, count: 4096)
        var buffer = Data()
        while stream.hasBytesAvailable {
            let count = stream.read(&bytes, maxLength: bytes.count)
            guard count > 0 else { break }
            buffer.append(contentsOf: bytes.prefix(count))
        }
        data = buffer
    } else { throw LLMError.invalidResponse("Missing request body") }
    return try JSONDecoder().decode([String: JSONValue].self, from: data)
}

@Test func responsesWireContract() throws {
    let tool = LLMTool(name: "roll_dice", description: "Roll RPG dice.", parameters: .object([
        "type": .string("object"), "properties": .object(["sides": .object(["type": .string("integer")])]),
        "required": .array([.string("sides")]), "additionalProperties": .bool(false),
    ]))
    let request = LLMRequest(
        model: "test-model", input: [.message(.user, "Open the door")], instructions: "You are the GM.",
        tools: [tool], toolChoice: .function(name: "roll_dice"), parallelToolCalls: false,
        maxOutputTokens: 500, reasoning: .init(effort: "low")
    )
    for (service, endpoint) in [
        (ResponsesService.openAI(apiKey: "test-key"), "https://api.openai.com/v1/responses"),
        (ResponsesService.openRouter(apiKey: "test-key", appURL: URL(string: "https://epoch.example"), appName: "Epoch"),
         "https://openrouter.ai/api/v1/responses"),
    ] {
        for streaming in [true, false] {
            let wire = try service.makeRequest(request, streaming: streaming)
            let body = try requestBody(wire)
            #expect(wire.url?.absoluteString == endpoint)
            #expect(wire.httpMethod == "POST")
            #expect(wire.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
            #expect(wire.value(forHTTPHeaderField: "Content-Type") == "application/json")
            #expect(body["store"] == .bool(false))
            #expect(body["stream"] == .bool(streaming))
            #expect(body["include"] == .array([.string("reasoning.encrypted_content")]))
            #expect(body["messages"] == nil)
            #expect(body["previous_response_id"] == nil)
            #expect(body["tool_choice"] == .object(["type": .string("function"), "name": .string("roll_dice")]))
            let fields = try #require(body["tools"]?.array?.first?.object)
            #expect(fields["name"] == .string("roll_dice"))
            #expect(fields["type"] == .string("function"))
            #expect(fields["strict"] == .bool(true))
            #expect(fields["function"] == nil)
            if service.id == .openRouter {
                #expect(wire.value(forHTTPHeaderField: "HTTP-Referer") == "https://epoch.example")
                #expect(wire.value(forHTTPHeaderField: "X-Title") == "Epoch")
            }
        }
    }
}

@Test func responseAndStatelessToolContinuation() throws {
    let response = try decodeResponse()
    #expect(response.text == "The door opens. Roll initiative.")
    #expect(response.refusals == ["Cannot do that."])
    #expect(response.toolCalls.map(\.callID) == ["call_1", "call_2"])
    #expect(response.usage?.totalTokens == 25)
    struct DiceArguments: Decodable { let sides: Int }
    let call = try #require(response.toolCalls.first)
    #expect(try call.decodeArguments(as: DiceArguments.self).sides == 20)
    var request = LLMRequest(model: "test-model", input: [.message(.user, "Open the door")])
    request.append(response)
    request.input.append(try .toolResult(callID: call.callID, output: ["roll": 17]))
    let body = try JSONDecoder().decode([String: JSONValue].self, from: JSONEncoder().encode(request))
    let items = try #require(body["input"]?.array)
    #expect(items.count == 6)
    #expect(items[1].object?["encrypted_content"] == .string("opaque"))
    #expect(items[1].object?["future_field"] == .object(["x": .integer(1)]))
    #expect(items[5].object?["type"] == .string("function_call_output"))
    #expect(items[5].object?["call_id"] == .string("call_1"))
    #expect(items[5].object?["output"] == .string(#"{"roll":17}"#))
    #expect(try JSONDecoder().decode(LLMResponse.self, from: JSONEncoder().encode(response)) == response)
}

@Test func incompleteResponseRemainsVisible() throws {
    let response = try decodeResponse(mixedResponse.replacingOccurrences(of: #""status":"completed""#, with: #""status":"incomplete""#))
    #expect(!response.isComplete)
    #expect(try response.validated().text == "The door opens. Roll initiative.")
}

@Test func malformedFunctionCallsAndArgumentsAreRejected() throws {
    var fields = try #require(decodeResponse().output.first { $0.type == "function_call" }).fields
    fields.removeValue(forKey: "call_id")
    let malformed = LLMResponse(id: "test", model: "test", status: "completed", output: [.init(fields: fields)])
    #expect(throws: LLMError.self) { try malformed.validated() }
    let call = LLMToolCall(callID: "call_1", name: "dice", arguments: "{broken")
    #expect(throws: DecodingError.self) { try call.decodeArguments(as: [String: Int].self) }
}

@Test func jsonValuesRoundTrip() throws {
    let value = JSONValue.object([
        "string": .string("旅人"), "int": .integer(20), "number": .number(1.5),
        "bool": .bool(true), "array": .array([.null, .object([:])]),
    ])
    #expect(try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value)) == value)
}

@Test(arguments: ["\n", "\r\n", "\r"])
func sseFramingPreservesMultilineAndUnicode(newline: String) throws {
    let source = [": heartbeat", "event: response.output_text.delta", "data: {\"type\":\"response.output_text.delta\",",
                  "data: \"delta\":\"旅人 ⚔️\"}", "", "data: [DONE]", "", ""].joined(separator: newline)
    var parser = ServerSentEventParser()
    var frames: [Data] = []
    for byte in source.utf8 {
        if let frame = try parser.append(byte) { frames.append(frame) }
    }
    #expect(frames.count == 2)
    #expect(try ResponsesStreamDecoder.decode(frames[0]) == .textDelta("旅人 ⚔️"))
    #expect(try ResponsesStreamDecoder.decode(frames[1]) == nil)
}

@Test func streamingDecodesToolsAndTerminalResponse() throws {
    let fragments = [
        #"{"type":"response.output_item.added","output_index":2,"item":{"type":"function_call","id":"fc_1","call_id":"call_1","name":"roll_dice","arguments":""}}"#,
        #"{"type":"response.function_call_arguments.delta","output_index":2,"item_id":"fc_1","delta":"{\"sides\":"}"#,
        #"{"type":"response.function_call_arguments.delta","output_index":2,"item_id":"fc_1","delta":"20}"}"#,
        "{\"type\":\"response.completed\",\"response\":\(mixedResponse)}",
    ]
    let events = try fragments.compactMap { try ResponsesStreamDecoder.decode(Data($0.utf8)) }
    #expect(events.count == 4)
    #expect(events[1] == .toolArgumentsDelta(index: 2, itemID: "fc_1", delta: #"{"sides":"#))
    #expect(events[2] == .toolArgumentsDelta(index: 2, itemID: "fc_1", delta: "20}"))
    #expect(events[3] == .response(try decodeResponse()))
}

@Test func streamingErrorsAndUnknownEvents() throws {
    for json in [
        #"{"type":"error","message":"Rate limited","code":429}"#,
        #"{"type":"error","error":{"message":"Invalid key","code":"invalid_api_key"}}"#,
        #"{"type":"response.output_text.delta"}"#,
        #"{"type":"response.completed"}"#,
        #"{"type":"response.failed","response":{"id":"resp_1","model":"test","status":"failed","output":[],"error":{"code":"oops","message":"Failed"}}}"#,
    ] {
        #expect(throws: LLMError.self) { try ResponsesStreamDecoder.decode(Data(json.utf8)) }
    }
    #expect(try ResponsesStreamDecoder.decode(Data(#"{"type":"future.event"}"#.utf8)) == nil)
    #expect(try ResponsesStreamDecoder.decode(Data(#"{"type":"response.refusal.delta","delta":"No"}"#.utf8)) == .refusalDelta("No"))
}

@Test func requestConfigurationValidation() throws {
    let request = LLMRequest(model: "test", input: [.message(.user, "hello")])
    for service in [
        ResponsesService.openAI(apiKey: " "),
        ResponsesService.openAI(apiKey: "test", timeoutInterval: -1),
        ResponsesService(id: .openAI, baseURL: URL(string: "file:///tmp")!, apiKey: "test"),
    ] {
        #expect(throws: LLMError.self) { try service.makeRequest(request, streaming: false) }
    }
    #expect(throws: LLMError.self) {
        try ResponsesService.openAI(apiKey: "test").makeRequest(.init(model: "", input: []), streaming: false)
    }
}

private let cancellationStopped = AsyncStream<Void>.makeStream()

// No credentials, live calls, shared mutable handlers, or timing-dependent mocks.
private final class FixtureProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {
        if request.value(forHTTPHeaderField: "X-Test-Cancel") == "true" {
            cancellationStopped.continuation.yield(())
            cancellationStopped.continuation.finish()
        }
    }

    override func startLoading() {
        do {
            let body = try requestBody(request)
            let model = body["model"]?.string ?? ""
            let streaming = body["stream"] == .bool(true)
            #expect(body["store"] == .bool(false))
            var status = 200
            var contentType = "application/json"
            var reply = mixedResponse
            switch model {
            case "http-error":
                status = 429
                reply = #"{"error":{"message":"Slow down","code":429}}"#
            case "bad-json": reply = "{broken"
            case "failed":
                reply = #"{"id":"resp_1","model":"test","status":"failed","output":[],"error":{"message":"Failed","code":"oops"}}"#
            default:
                if streaming {
                    contentType = "text/event-stream"
                    reply = "data: {\"type\":\"response.output_text.delta\",\"delta\":\"Hello ⚔️\"}\r\n\r\n"
                    switch model {
                    case "cancel": break
                    case "truncated": reply += "data: [DONE]\n\n"
                    case "stream-error": reply += "data: {\"type\":\"error\",\"message\":\"Broken\",\"code\":500}\n\n"
                    case "wrong-content-type": contentType = "application/json"
                    default:
                        let compact = String(decoding: try JSONEncoder().encode(decodeResponse()), as: UTF8.self)
                        reply += "data: {\"type\":\"response.completed\",\"response\":\(compact)}\n\n"
                    }
                }
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                                           headerFields: ["Content-Type": contentType, "Retry-After": "2"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            // Splitting into tiny chunks exercises UTF-8 and SSE framing.
            let bytes = Array(reply.utf8)
            for start in stride(from: 0, to: bytes.count, by: 7) {
                client?.urlProtocol(self, didLoad: Data(bytes[start..<min(start + 7, bytes.count)]))
            }
            if model != "cancel" { client?.urlProtocolDidFinishLoading(self) }
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
}

private func fixtureSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [FixtureProtocol.self]
    return URLSession(configuration: configuration)
}

@Test func transportSendsAndStreamsForBothProviders() async throws {
    let session = fixtureSession()
    defer { session.invalidateAndCancel() }
    for service in [ResponsesService.openAI(apiKey: "test", session: session),
                    ResponsesService.openRouter(apiKey: "test", session: session)] {
        let request = LLMRequest(model: "test", input: [.message(.user, "Hello")])
        #expect(try await service.send(request) == decodeResponse())
        var events: [LLMStreamEvent] = []
        for try await event in service.stream(request) { events.append(event) }
        #expect(events == [.textDelta("Hello ⚔️"), .response(try decodeResponse())])
    }
}

@Test func transportPreservesHTTPErrors() async throws {
    let session = fixtureSession()
    defer { session.invalidateAndCancel() }
    let service = ResponsesService.openAI(apiKey: "test", session: session)
    let request = LLMRequest(model: "http-error", input: [])
    for streaming in [false, true] {
        do {
            if streaming { for try await _ in service.stream(request) {} }
            else { _ = try await service.send(request) }
            Issue.record("Expected HTTP failure")
        } catch LLMError.http(let status, let message, let code, let retryAfter) {
            #expect(status == 429)
            #expect(message == "Slow down")
            #expect(code == "429")
            #expect(retryAfter == "2")
        }
    }
}

@Test(arguments: ["truncated", "stream-error", "wrong-content-type"])
func transportRejectsUnsuccessfulStreams(model: String) async throws {
    let session = fixtureSession()
    defer { session.invalidateAndCancel() }
    let service = ResponsesService.openAI(apiKey: "test", session: session)
    await #expect(throws: LLMError.self) {
        for try await _ in service.stream(.init(model: model, input: [])) {}
    }
}

@Test(arguments: ["bad-json", "failed"])
func transportRejectsInvalidResponses(model: String) async throws {
    let session = fixtureSession()
    defer { session.invalidateAndCancel() }
    let service = ResponsesService.openAI(apiKey: "test", session: session)
    await #expect(throws: (any Error).self) { try await service.send(.init(model: model, input: [])) }
}

@Test func managerSwitchesProvidersWithoutChangingModels() async throws {
    let session = fixtureSession()
    defer { session.invalidateAndCancel() }
    let manager = EpochAIManager(service: ResponsesService.openAI(apiKey: "test", session: session))
    await manager.register(ResponsesService.openRouter(apiKey: "test", session: session))
    let request = LLMRequest(model: "test", input: [.message(.user, "Hello")])
    #expect(try await manager.send(request).text == "The door opens. Roll initiative.")
    try await manager.select(.openRouter)
    #expect(await manager.selectedService == .openRouter)
    #expect(try await manager.send(request, using: .openAI).toolCalls.count == 2)
    #expect(await manager.selectedService == .openRouter)
    var count = 0
    for try await _ in try await manager.stream(request) { count += 1 }
    #expect(count == 2)
    await #expect(throws: LLMError.self) { try await manager.select(.init(rawValue: "lmstudio")) }
    #expect(await manager.selectedService == .openRouter)
}

private actor RequestGate {
    private var waiting: CheckedContinuation<Void, Never>?
    private var started: CheckedContinuation<Void, Never>?
    private var hasStarted = false

    func pause() async {
        await withCheckedContinuation { continuation in
            waiting = continuation
            hasStarted = true
            started?.resume()
            started = nil
        }
    }
    func waitUntilStarted() async {
        if hasStarted { return }
        await withCheckedContinuation { started = $0 }
    }
    func release() { waiting?.resume(); waiting = nil }
}

private struct GatedService: EpochLLMService {
    let id: LLMServiceID
    let gate: RequestGate
    func send(_ request: LLMRequest) async throws -> LLMResponse {
        await gate.pause()
        return LLMResponse(id: id.rawValue, model: request.model, status: "completed", output: [])
    }
    func stream(_ request: LLMRequest) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}

@Test func switchingDoesNotRedirectInflightRequests() async throws {
    let gate = RequestGate()
    let customID = LLMServiceID(rawValue: "future-local-adapter")
    let manager = EpochAIManager(service: GatedService(id: customID, gate: gate))
    let pending = Task { try await manager.send(.init(model: "local-model", input: [])) }
    await gate.waitUntilStarted()
    await manager.register(ResponsesService.openAI(apiKey: "unused"))
    try await manager.select(.openAI)
    await gate.release()
    #expect(try await pending.value.id == customID.rawValue)
    #expect(await manager.selectedService == .openAI)
}


@Test(.timeLimit(.minutes(1)))
func cancellingStreamStopsNetworkRequest() async throws {
    let session = fixtureSession()
    defer { session.invalidateAndCancel() }
    let service = ResponsesService(
        id: .openAI, baseURL: URL(string: "https://api.openai.com/v1")!, apiKey: "test",
        headers: ["X-Test-Cancel": "true"], session: session
    )
    let received = AsyncStream<Void>.makeStream()
    let consumer = Task {
        for try await _ in service.stream(.init(model: "cancel", input: [])) {
            received.continuation.yield(())
        }
    }
    for await _ in received.stream { break }
    consumer.cancel()
    _ = await consumer.result
    var stopped = false
    for await _ in cancellationStopped.stream { stopped = true; break }
    #expect(stopped)
    received.continuation.finish()
}
