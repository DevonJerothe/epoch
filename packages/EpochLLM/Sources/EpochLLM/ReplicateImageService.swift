import Foundation

/// Only the official FLUX Schnell endpoint is supported. No automatic retries
/// create additional paid predictions. The caller owns persistence of images.
public struct ReplicateImageService: Sendable {
    public static let model = "black-forest-labs/flux-schnell"
    public let timeoutInterval: TimeInterval
    private let apiKey: String
    private let session: URLSession
    private let pollingInterval: TimeInterval
    private let baseURL = URL(string: "https://api.replicate.com/v1")!

    /// timeoutInterval bounds generation, polling, and downloading together.
    public init(
        apiKey: String, timeoutInterval: TimeInterval = 120,
        pollingInterval: TimeInterval = 1, session: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.timeoutInterval = timeoutInterval
        self.pollingInterval = pollingInterval
        self.session = session
    }

    public func generateImage(_ request: ImageGenerationRequest) async throws -> ImageGenerationResponse {
        let creation = try makeRequest(request)
        return try await withThrowingTaskGroup(of: ImageGenerationResponse.self) { group in
            defer { group.cancelAll() }
            group.addTask { try await generateImage(request, creation: creation) }
            group.addTask {
                try await ContinuousClock().sleep(for: .seconds(timeoutInterval))
                throw URLError(.timedOut)
            }
            return try await group.next()!
        }
    }

    private func generateImage(
        _ request: ImageGenerationRequest, creation: URLRequest
    ) async throws -> ImageGenerationResponse {
        var creation = creation
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(timeoutInterval))
        creation.timeoutInterval = try remainingTime(until: deadline)
        var prediction = try await fetchPrediction(creation)
        while true {
            try Task.checkCancellation()
            _ = try remainingTime(until: deadline)
            guard !prediction.id.isEmpty,
                  prediction.id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) else {
                throw LLMError.invalidResponse("Replicate returned an invalid prediction ID.")
            }
            switch prediction.status {
            case "succeeded":
                guard let output = prediction.output, output.count == 1,
                      let url = URL(string: output[0]), url.scheme == "https", url.host != nil else {
                    throw LLMError.invalidResponse("FLUX Schnell did not return one HTTPS image URL.")
                }
                // Do not send the Replicate API credential to the image host.
                var download = URLRequest(url: url)
                download.timeoutInterval = try remainingTime(until: deadline)
                let data = try await fetch(download, expectingImage: true)
                try Task.checkCancellation()
                _ = try remainingTime(until: deadline)
                guard !data.isEmpty else {
                    throw LLMError.invalidResponse("The generated image download was empty.")
                }
                return ImageGenerationResponse(
                    id: prediction.id, imageURL: url, imageData: data, outputFormat: request.outputFormat
                )
            case "failed", "canceled":
                throw LLMError.responseFailed(
                    message: prediction.error ?? "Replicate prediction \(prediction.status).", code: nil
                )
            case "starting", "processing":
                try await clock.sleep(for: .seconds(min(pollingInterval, try remainingTime(until: deadline))))
                var poll = URLRequest(url: baseURL.appendingPathComponent("predictions").appendingPathComponent(prediction.id))
                poll.timeoutInterval = try remainingTime(until: deadline)
                poll.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                poll.setValue("application/json", forHTTPHeaderField: "Accept")
                prediction = try await fetchPrediction(poll)
            default:
                throw LLMError.invalidResponse("Unexpected Replicate prediction status: \(prediction.status).")
            }
        }
    }

    func makeRequest(_ request: ImageGenerationRequest) throws -> URLRequest {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LLMError.invalidConfiguration("A Replicate API key is required.")
        }
        guard timeoutInterval.isFinite, timeoutInterval > 0,
              pollingInterval.isFinite, pollingInterval > 0 else {
            throw LLMError.invalidConfiguration("Timeout and polling intervals must be positive and finite.")
        }
        guard !request.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LLMError.invalidConfiguration("An image prompt is required.")
        }
        var result = URLRequest(url: baseURL.appendingPathComponent("models/\(Self.model)/predictions"))
        result.httpMethod = "POST"
        result.timeoutInterval = timeoutInterval
        result.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        result.setValue("application/json", forHTTPHeaderField: "Content-Type")
        result.setValue("application/json", forHTTPHeaderField: "Accept")
        result.setValue("wait", forHTTPHeaderField: "Prefer")
        let input: [String: JSONValue] = [
            "prompt": .string(request.prompt), "aspect_ratio": .string(request.aspectRatio.rawValue),
            "output_format": .string(request.outputFormat.rawValue),
            "num_outputs": .integer(1), "num_inference_steps": .integer(4),
        ]
        result.httpBody = try JSONEncoder().encode(["input": input])
        return result
    }

    private func remainingTime(until deadline: ContinuousClock.Instant) throws -> TimeInterval {
        try Task.checkCancellation()
        let remaining = ContinuousClock().now.duration(to: deadline).components
        let seconds = Double(remaining.seconds) + Double(remaining.attoseconds) / 1e18
        guard seconds > 0 else { throw URLError(.timedOut) }
        return seconds
    }

    private func fetchPrediction(_ request: URLRequest) async throws -> Prediction {
        try JSONDecoder().decode(Prediction.self, from: await fetch(request))
    }

    private func fetch(_ request: URLRequest, expectingImage: Bool = false) async throws -> Data {
        try Task.checkCancellation()
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse("Expected an HTTP response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            struct APIError: Decodable { let detail: String? }
            let detail = try? JSONDecoder().decode(APIError.self, from: data).detail
            throw LLMError.http(
                status: http.statusCode,
                message: detail ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode),
                code: nil, retryAfter: http.value(forHTTPHeaderField: "Retry-After")
            )
        }
        if expectingImage, let contentType = http.value(forHTTPHeaderField: "Content-Type"),
           !contentType.lowercased().hasPrefix("image/") {
            throw LLMError.invalidResponse("Expected image data from the generated image URL.")
        }
        return data
    }
}

private struct Prediction: Decodable {
    let id: String
    let status: String
    let output: [String]?
    let error: String?
}
