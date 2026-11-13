import CoreGraphics
import EpochLLM
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Stable across launches and devices, unlike `Hasher`, which is seeded per process.
nonisolated enum FixtureSeed {
    static func hash(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01b3
        }
        return hash
    }

    static func identifier(_ seed: UInt64) -> String {
        "fixture-" + String(seed, radix: 16)
    }
}

/// A narrator that makes no network requests and costs nothing. The same conversation always
/// produces the same passage, so development flows and UI tests are repeatable. It narrates
/// only: it never returns tool calls, whatever tools the request offers.
nonisolated struct FixtureTextService: EpochLLMService {
    static let serviceID = LLMServiceID(rawValue: "fixture")
    static let defaultModel = "fixture-narrator"
    static let modelInfo = LLMModelInfo(
        id: defaultModel, name: "Fixture Narrator",
        summary: "Deterministic passages for development. No requests are sent."
    )

    static let passages = [
        "The road narrows between two leaning stones, and beyond them the valley opens like a turned page. Smoke rises from a single chimney below. Somewhere near, water is running over rock.",
        "Rain has left the courtyard dark and shining. A lantern swings on its hook by the stable door, though no wind moves it. From inside comes the slow sound of something breathing.",
        "The archivist does not look up. \"You are late,\" she says, sliding a ledger across the desk, \"or early. It depends which of us is keeping the count.\" The ink on the open line is still wet.",
        "Below the chapel the stair turns twice and ends at a door of black oak, banded in iron. There is no handle on this side. Scratched into the wood, at the height of a child, is a single word: wait.",
        "Morning comes grey over the marsh. The ferryman has already untied the boat and stands with one foot on the gunwale, watching you, his pole laid across his shoulders like a yoke.",
    ]

    let id = Self.serviceID
    /// Pause before each streamed chunk, so streaming UI can be seen working.
    var chunkDelay: Duration = .milliseconds(30)

    func send(_ request: LLMRequest) async throws -> LLMResponse {
        Self.response(for: request)
    }

    func stream(_ request: LLMRequest) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        let response = Self.response(for: request)
        let delay = chunkDelay
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for chunk in Self.chunks(of: response.text) {
                        try await Task.sleep(for: delay)
                        continuation.yield(.textDelta(chunk))
                    }
                    continuation.yield(.response(response))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static func response(for request: LLMRequest) -> LLMResponse {
        let userTurns = request.input.compactMap(userText)
        // The turn count is part of the seed so repeating an action later in a story reads differently.
        let seed = FixtureSeed.hash("\(userTurns.count)|\(userTurns.last ?? "")")
        let text = passages[Int(seed % UInt64(passages.count))]
        let identifier = FixtureSeed.identifier(seed)
        let message = LLMItem(fields: [
            "type": .string("message"),
            "id": .string("msg-\(identifier)"),
            "role": .string(LLMRole.assistant.rawValue),
            "status": .string("completed"),
            "content": .array([.object([
                "type": .string("output_text"), "text": .string(text), "annotations": .array([]),
            ])]),
        ])
        let inputTokens = userTurns.reduce(0) { $0 + wordCount($1) } + wordCount(request.instructions ?? "")
        let outputTokens = wordCount(text)
        return LLMResponse(
            id: identifier, model: request.model, status: "completed", output: [message],
            usage: LLMUsage(
                inputTokens: inputTokens, outputTokens: outputTokens, totalTokens: inputTokens + outputTokens
            )
        )
    }

    /// Word-sized pieces that join back into exactly `text`.
    static func chunks(of text: String) -> [String] {
        let words = text.split(separator: " ", omittingEmptySubsequences: false)
        return words.enumerated().map { index, word in
            index == words.count - 1 ? String(word) : String(word) + " "
        }
    }

    private static func userText(_ item: LLMItem) -> String? {
        guard item.fields["role"]?.string == LLMRole.user.rawValue else { return nil }
        switch item.fields["content"] {
        case .string(let text)?:
            return text
        case .array(let parts)?:
            return parts.compactMap { $0.object?["text"]?.string }.joined(separator: " ")
        default:
            return nil
        }
    }

    private static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }
}

/// A decision provider that makes no network requests. Each answer depends only on the state
/// and the question, so the same scene is always judged the same way. It never refuses.
nonisolated struct FixtureDecisionService: EpochDecisionService {
    static let defaultModel = "fixture-arbiter"
    static let modelInfo = LLMModelInfo(
        id: defaultModel, name: "Fixture Arbiter",
        summary: "Deterministic answers for development. No requests are sent."
    )

    let id = FixtureTextService.serviceID

    func decide(_ request: DecisionRequest) async throws -> DecisionResponse {
        guard !request.questions.isEmpty else {
            throw LLMError.invalidConfiguration("A decision needs at least one question.")
        }
        let state: String
        switch request.state {
        case .text(let text):
            state = text
        case .json(let value):
            // Sorted keys keep the seed stable; dictionary order is not.
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            state = String(decoding: try encoder.encode(value), as: UTF8.self)
        }
        var answers: [String: DecisionAnswer] = [:]
        for question in request.questions {
            let seed = FixtureSeed.hash("\(state)|\(question.name)|\(question.instructions)")
            answers[question.name] = Self.answer(to: question.kind, seed: seed)
        }
        return DecisionResponse(model: request.model, answers: answers)
    }

    /// The favoured outcome gets 0.8 and the rest share 0.2, so thresholds behave predictably.
    private static func answer(to kind: DecisionQuestion.Kind, seed: UInt64) -> DecisionAnswer {
        switch kind {
        case .predicate:
            return .predicate(probability: seed % 2 == 0 ? 0.8 : 0.2, confidence: 0.8)
        case .choice(let options):
            guard !options.isEmpty else { return .refusal }
            let chosen = Int(seed % UInt64(options.count))
            let probabilities = distribution(count: options.count, favoured: chosen)
            return .choice(DecisionChoiceAnswer(
                choice: options[chosen].value, confidence: 0.8,
                probabilities: Dictionary(
                    zip(options.map(\.value), probabilities), uniquingKeysWith: { first, _ in first }
                )
            ))
        case .score(let levels):
            guard !levels.isEmpty else { return .refusal }
            let chosen = Int(seed % UInt64(levels.count))
            let probabilities = distribution(count: levels.count, favoured: chosen)
            let expected = probabilities.enumerated().reduce(0) { $0 + Double($1.offset) * $1.element }
            return .score(DecisionScoreAnswer(
                score: expected, confidence: 0.8,
                levels: levels.enumerated().map { index, level in
                    .init(index: index, label: level.label, probability: probabilities[index])
                }
            ))
        }
    }

    private static func distribution(count: Int, favoured: Int) -> [Double] {
        guard count > 1 else { return [1] }
        let rest = 0.2 / Double(count - 1)
        return (0..<count).map { $0 == favoured ? 0.8 : rest }
    }
}

/// An illustrator that makes no network requests. It draws a flat sepia plate whose tones
/// depend only on the prompt and aspect ratio. WebP requests are answered with PNG, which the
/// response's `outputFormat` reports.
nonisolated struct FixtureImageService: EpochImageService {
    private static let longestSide = 512.0

    func generateImage(_ request: ImageGenerationRequest) async throws -> ImageGenerationResponse {
        guard !request.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LLMError.invalidConfiguration("An image prompt is required.")
        }
        let seed = FixtureSeed.hash("\(request.aspectRatio.rawValue)|\(request.prompt)")
        let format: ImageOutputFormat = request.outputFormat == .jpg ? .jpg : .png
        let identifier = FixtureSeed.identifier(seed)
        // `.invalid` never resolves, so nothing can mistake this for a downloadable image.
        guard let url = URL(string: "https://fixtures.epoch.invalid/\(identifier).\(format.rawValue)") else {
            throw LLMError.invalidResponse("The fixture image URL could not be formed.")
        }
        let data = try Self.render(aspectRatio: request.aspectRatio, seed: seed, format: format)
        return ImageGenerationResponse(id: identifier, imageURL: url, imageData: data, outputFormat: format)
    }

    private static func render(
        aspectRatio: ImageAspectRatio, seed: UInt64, format: ImageOutputFormat
    ) throws -> Data {
        let parts = aspectRatio.rawValue.split(separator: ":").compactMap { Double($0) }
        guard parts.count == 2, parts[0] > 0, parts[1] > 0 else {
            throw LLMError.invalidResponse("Unsupported fixture aspect ratio: \(aspectRatio.rawValue).")
        }
        let scale = longestSide / max(parts[0], parts[1])
        let width = Int((parts[0] * scale).rounded())
        let height = Int((parts[1] * scale).rounded())
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            throw LLMError.invalidResponse("The fixture image could not be drawn.")
        }
        // Sky, then ground rising to a seed-dependent horizon. Origin is bottom-left.
        let tone = Double(seed % 32) / 255
        let horizon = 0.3 + Double((seed >> 8) % 30) / 100
        context.setFillColor(red: 0.84 - tone, green: 0.78 - tone, blue: 0.66 - tone, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(red: 0.52 - tone, green: 0.44 - tone, blue: 0.33 - tone, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: Double(width), height: Double(height) * horizon))

        let type: UTType = format == .jpg ? .jpeg : .png
        let data = NSMutableData()
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else {
            throw LLMError.invalidResponse("The fixture image could not be encoded.")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw LLMError.invalidResponse("The fixture image could not be encoded.")
        }
        return data as Data
    }
}
