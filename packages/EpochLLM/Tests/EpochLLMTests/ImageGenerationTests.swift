import Foundation
import os
import Testing
@testable import EpochLLM

private let imageBytes = Data([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])

private final class ImageFixtureProtocol: URLProtocol, @unchecked Sendable {
    struct CancellationSignals: Sendable {
        let started: AsyncStream<Void>.Continuation
        let stopped: AsyncStream<Void>.Continuation
    }

    static let cancellationHeader = "X-Image-Cancellation-Test-ID"
    // URLProtocol callbacks can run concurrently with test registration and cleanup.
    static let cancellationSignals = OSAllocatedUnfairLock(initialState: [String: CancellationSignals]())

    private var signals: CancellationSignals? {
        guard let id = request.value(forHTTPHeaderField: Self.cancellationHeader) else { return nil }
        return Self.cancellationSignals.withLock { $0[id] }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {
        if request.url?.lastPathComponent == "cancel" {
            signals?.stopped.yield(())
            signals?.stopped.finish()
        }
    }

    override func startLoading() {
        do {
            let url = try #require(request.url)
            var status = 200
            var reply: Data
            var headers = ["Content-Type": "application/json", "Retry-After": "2"]
            if url.host == "images.example" {
                #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
                #expect(request.httpMethod == "GET")
                headers["Content-Type"] = "image/png"
                switch url.lastPathComponent {
                case "empty": reply = Data()
                case "download-error": status = 403; reply = Data()
                case "not-image": headers["Content-Type"] = "text/html"; reply = Data("An error page".utf8)
                case "download-timeout": return
                default: reply = imageBytes
                }
            } else {
                #expect(url.host == "api.replicate.com")
                #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
                #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
                var scenario = url.lastPathComponent
                if request.httpMethod == "POST" {
                    #expect(url.path == "/v1/models/black-forest-labs/flux-schnell/predictions")
                    #expect(request.value(forHTTPHeaderField: "Prefer") == "wait")
                    let body = try bodyJSON(request)
                    let input = try #require(body["input"]?.object)
                    #expect(input["num_outputs"] == .integer(1))
                    #expect(input["num_inference_steps"] == .integer(4))
                    #expect(body["model"] == nil)
                    #expect(body["version"] == nil)
                    scenario = try #require(input["prompt"]?.string)
                    if ["poll", "processing-output", "cancel", "poll-timeout"].contains(scenario) {
                        let outputs: [String]? = scenario == "processing-output" ? ["https://images.example/poll"] : nil
                        reply = try prediction(scenario, status: "processing", output: outputs)
                    } else if scenario == "http-error" {
                        status = 429
                        reply = Data(#"{"detail":"Slow down"}"#.utf8)
                    } else if scenario == "bad-json" {
                        reply = Data("{broken".utf8)
                    } else if scenario == "timeout" {
                        return // Remains open until the service deadline cancels it.
                    } else {
                        switch scenario {
                        case "failed", "canceled": reply = try prediction(scenario, status: scenario, error: "Generation stopped")
                        case "unknown": reply = try prediction(scenario, status: "unexpected")
                        case "missing": reply = try prediction(scenario, status: "succeeded")
                        case "no-images": reply = try prediction(scenario, status: "succeeded", output: [])
                        case "multiple": reply = try prediction(scenario, status: "succeeded", output: ["https://images.example/1", "https://images.example/2"])
                        case "bad-url": reply = try prediction(scenario, status: "succeeded", output: ["file:///tmp/image.png"])
                        case "bad-id": reply = try prediction("../secret", status: "processing")
                        default: reply = try prediction(scenario, status: "succeeded", output: ["https://images.example/\(scenario)"])
                        }
                    }
                } else {
                    #expect(request.httpMethod == "GET")
                    #expect(url.path == "/v1/predictions/\(scenario)")
                    if scenario == "cancel" {
                        signals?.started.yield(())
                        signals?.started.finish()
                        return
                    }
                    if scenario == "poll-timeout" {
                        reply = try prediction(scenario, status: "processing")
                    } else {
                        reply = try prediction(scenario, status: "succeeded", output: ["https://images.example/\(scenario)"])
                    }
                }
            }
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: reply)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
}

private func prediction(_ id: String, status: String, output: [String]? = nil, error: String? = nil) throws -> Data {
    var fields: [String: JSONValue] = ["id": .string(id), "status": .string(status)]
    fields["output"] = output.map { .array($0.map { .string($0) }) } ?? .null
    fields["error"] = error.map { .string($0) } ?? .null
    // A response-provided poll URL must never control credential routing.
    fields["urls"] = .object(["get": .string("https://untrusted.example/prediction")])
    return try JSONEncoder().encode(fields)
}

private func bodyJSON(_ request: URLRequest) throws -> [String: JSONValue] {
    let data: Data
    if let body = request.httpBody { data = body }
    else {
        let stream = try #require(request.httpBodyStream)
        stream.open()
        defer { stream.close() }
        var buffer = [UInt8](repeating: 0, count: 4096)
        var body = Data()
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            body.append(contentsOf: buffer.prefix(count))
        }
        data = body
    }
    return try JSONDecoder().decode([String: JSONValue].self, from: data)
}

private func imageSession(cancellationID: String? = nil) -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ImageFixtureProtocol.self]
    if let cancellationID {
        configuration.httpAdditionalHeaders = [ImageFixtureProtocol.cancellationHeader: cancellationID]
    }
    return URLSession(configuration: configuration)
}

@Test func fluxSchnellWireContract() throws {
    let service = ReplicateImageService(apiKey: "test-key")
    let wire = try service.makeRequest(.init(prompt: "A moonlit tavern", aspectRatio: .landscape, outputFormat: .jpg))
    let input = try #require(bodyJSON(wire)["input"]?.object)
    #expect(input["prompt"] == .string("A moonlit tavern"))
    #expect(input["aspect_ratio"] == .string("16:9"))
    #expect(input["output_format"] == .string("jpg"))
    #expect(input["num_outputs"] == .integer(1))
    #expect(input["num_inference_steps"] == .integer(4))
    #expect(wire.url?.absoluteString == "https://api.replicate.com/v1/models/black-forest-labs/flux-schnell/predictions")
    #expect(wire.httpMethod == "POST")
    #expect(wire.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
    #expect(wire.value(forHTTPHeaderField: "Content-Type") == "application/json")
    #expect(wire.value(forHTTPHeaderField: "Prefer") == "wait")
    let defaults = ImageGenerationRequest(prompt: "A tavern")
    #expect(defaults.aspectRatio == .square)
    #expect(defaults.outputFormat == .png)
}

@Test(arguments: ["success", "poll", "processing-output"])
func imageGenerationReturnsURLAndDownloadedData(scenario: String) async throws {
    let session = imageSession()
    defer { session.invalidateAndCancel() }
    let service = ReplicateImageService(apiKey: "test-key", pollingInterval: 0.001, session: session)
    let response = try await service.generateImage(.init(prompt: scenario))
    #expect(response.id == scenario)
    #expect(response.imageURL.absoluteString == "https://images.example/\(scenario)")
    #expect(response.imageData == imageBytes)
    #expect(response.outputFormat == .png)
}

@Test(arguments: ["failed", "canceled", "unknown", "missing", "no-images", "multiple", "bad-url", "bad-id", "empty", "not-image"])
func imageGenerationRejectsInvalidPredictions(scenario: String) async throws {
    let session = imageSession()
    defer { session.invalidateAndCancel() }
    let service = ReplicateImageService(apiKey: "test-key", session: session)
    await #expect(throws: LLMError.self) { try await service.generateImage(.init(prompt: scenario)) }
}

@Test func imageGenerationPreservesErrors() async throws {
    let session = imageSession()
    defer { session.invalidateAndCancel() }
    let service = ReplicateImageService(apiKey: "test-key", session: session)
    do {
        _ = try await service.generateImage(.init(prompt: "http-error"))
        Issue.record("Expected HTTP error")
    } catch LLMError.http(let status, let message, let code, let retryAfter) {
        #expect(status == 429)
        #expect(message == "Slow down")
        #expect(code == nil)
        #expect(retryAfter == "2")
    }
    do {
        _ = try await service.generateImage(.init(prompt: "download-error"))
        Issue.record("Expected download error")
    } catch LLMError.http(let status, _, _, _) { #expect(status == 403) }
    await #expect(throws: DecodingError.self) { try await service.generateImage(.init(prompt: "bad-json")) }
    do {
        _ = try await service.generateImage(.init(prompt: "failed"))
        Issue.record("Expected generation failure")
    } catch LLMError.responseFailed(let message, _) { #expect(message == "Generation stopped") }
}

@Test func imageConfigurationValidation() throws {
    for service in [
        ReplicateImageService(apiKey: " "),
        ReplicateImageService(apiKey: "test", timeoutInterval: 0),
        ReplicateImageService(apiKey: "test", timeoutInterval: .infinity),
        ReplicateImageService(apiKey: "test", pollingInterval: -1),
        ReplicateImageService(apiKey: "test", pollingInterval: .nan),
    ] {
        #expect(throws: LLMError.self) { try service.makeRequest(.init(prompt: "A tavern")) }
    }
    #expect(throws: LLMError.self) {
        try ReplicateImageService(apiKey: "test").makeRequest(.init(prompt: " \n"))
    }
}

@Test(.timeLimit(.minutes(1)), arguments: ["timeout", "poll-timeout", "download-timeout"])
func imageGenerationDeadlineStopsWaiting(scenario: String) async throws {
    let session = imageSession()
    defer { session.invalidateAndCancel() }
    let service = ReplicateImageService(apiKey: "test-key", timeoutInterval: 0.05, pollingInterval: 0.001, session: session)
    do {
        _ = try await service.generateImage(.init(prompt: scenario))
        Issue.record("Expected deadline")
    } catch let error as URLError { #expect(error.code == .timedOut) }
}

@Test(.timeLimit(.minutes(1))) func cancellingImageGenerationStopsPolling() async throws {
    let imageRequestStarted = AsyncStream<Void>.makeStream()
    let imageRequestStopped = AsyncStream<Void>.makeStream()
    let cancellationID = UUID().uuidString
    ImageFixtureProtocol.cancellationSignals.withLock {
        $0[cancellationID] = .init(
            started: imageRequestStarted.continuation,
            stopped: imageRequestStopped.continuation
        )
    }
    let session = imageSession(cancellationID: cancellationID)
    defer {
        session.invalidateAndCancel()
        ImageFixtureProtocol.cancellationSignals.withLock { $0[cancellationID] = nil }
        imageRequestStarted.continuation.finish()
        imageRequestStopped.continuation.finish()
    }
    let service = ReplicateImageService(apiKey: "test-key", pollingInterval: 0.001, session: session)
    let task = Task { try await service.generateImage(.init(prompt: "cancel")) }
    for await _ in imageRequestStarted.stream { break }
    task.cancel()
    switch await task.result {
    case .success: Issue.record("Canceled generation should not return an image")
    case .failure(let error):
        #expect(error is CancellationError || (error as? URLError)?.code == .cancelled)
    }
    var stopped = false
    for await _ in imageRequestStopped.stream { stopped = true; break }
    #expect(stopped)
}

@Test func managerGeneratesImagesIndependentlyOfTextProvider() async throws {
    let session = imageSession()
    defer { session.invalidateAndCancel() }
    let text = ResponsesService.openRouter(apiKey: "unused")
    let manager = EpochAIManager(service: text)
    await #expect(throws: LLMError.self) { try await manager.generateImage(.init(prompt: "success")) }
    let images = ReplicateImageService(apiKey: "test-key", session: session)
    await manager.configureImageGeneration(images)
    #expect(try await manager.generateImage(.init(prompt: "success")).imageData == imageBytes)
    #expect(await manager.selectedService == .openRouter)
    let configured = EpochAIManager(service: text, imageService: images)
    #expect(try await configured.generateImage(.init(prompt: "success")).imageData == imageBytes)
}
