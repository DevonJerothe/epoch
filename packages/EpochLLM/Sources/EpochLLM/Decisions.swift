import Foundation

/// A provider-neutral set of questions about one shared state. Adapters
/// translate it to OpenAI's `input` + question array or to the TypeSafe System
/// One `state` + question map used by OpenRouter and Jev.
public struct DecisionRequest: Equatable, Sendable {
    public var model: String
    public var state: DecisionState
    /// Each name must be unique; answers are keyed by it.
    public var questions: [DecisionQuestion]

    public init(model: String, state: DecisionState, questions: [DecisionQuestion]) {
        self.model = model
        self.state = state
        self.questions = questions
    }
}

/// The content every question refers to.
public enum DecisionState: Equatable, Sendable {
    case text(String)
    /// Structured game state. OpenAI receives it as compact JSON text.
    case json(JSONValue)

    /// Encodes an app type (e.g. a scene snapshot) as structured state.
    public static func encoding<T: Encodable>(_ value: T) throws -> Self {
        let data = try JSONEncoder().encode(value)
        return .json(try JSONDecoder().decode(JSONValue.self, from: data))
    }
}

public struct DecisionQuestion: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// OpenAI "predicate" / TypeSafe "noul": the probability a statement is true.
        case predicate(whenTrue: String?, whenFalse: String?)
        case choice([DecisionOption])
        /// Levels are ordered lowest to highest; a level's index is its score.
        case score([DecisionLevel])
    }

    public var name: String
    public var instructions: String
    public var kind: Kind

    public init(name: String, instructions: String, kind: Kind) {
        self.name = name
        self.instructions = instructions
        self.kind = kind
    }

    /// `whenTrue`/`whenFalse` map to TypeSafe criteria. OpenAI has no criteria
    /// field, so they are appended to its instructions.
    public static func predicate(
        _ name: String, _ instructions: String, whenTrue: String? = nil, whenFalse: String? = nil
    ) -> Self {
        Self(name: name, instructions: instructions, kind: .predicate(whenTrue: whenTrue, whenFalse: whenFalse))
    }

    public static func choice(_ name: String, _ instructions: String, options: [DecisionOption]) -> Self {
        Self(name: name, instructions: instructions, kind: .choice(options))
    }

    public static func score(_ name: String, _ instructions: String, levels: [DecisionLevel]) -> Self {
        Self(name: name, instructions: instructions, kind: .score(levels))
    }
}

public struct DecisionOption: Equatable, Sendable, ExpressibleByStringLiteral {
    public var value: String
    public var description: String?

    public init(_ value: String, description: String? = nil) {
        self.value = value
        self.description = description
    }
    public init(stringLiteral value: String) { self.init(value) }
}

public struct DecisionLevel: Equatable, Sendable, ExpressibleByStringLiteral {
    public var label: String
    public var description: String?

    public init(_ label: String, description: String? = nil) {
        self.label = label
        self.description = description
    }
    public init(stringLiteral value: String) { self.init(value) }
}

// MARK: - Responses

public struct DecisionResponse: Equatable, Sendable {
    /// OpenRouter's generation ID; OpenAI and Jev do not return one.
    public let id: String?
    /// The resolved model, which can differ from a requested alias.
    public let model: String
    /// The upstream provider reported by OpenRouter.
    public let provider: String?
    /// Keyed by question name. Every question has an answer or a refusal.
    public let answers: [String: DecisionAnswer]
    public let usage: DecisionUsage?
    /// The full response body, for provider fields not modeled here.
    public let raw: JSONValue

    public init(
        id: String? = nil, model: String, provider: String? = nil,
        answers: [String: DecisionAnswer], usage: DecisionUsage? = nil, raw: JSONValue = .null
    ) {
        self.id = id
        self.model = model
        self.provider = provider
        self.answers = answers
        self.usage = usage
        self.raw = raw
    }

    public subscript(name: String) -> DecisionAnswer? { answers[name] }
}

/// Answers keep the provider's probability distributions rather than reducing
/// results to a single value. Any question can be refused independently.
public enum DecisionAnswer: Equatable, Sendable {
    /// Probability (0...1) that the statement is true.
    case predicate(probability: Double, confidence: Double?)
    case choice(DecisionChoiceAnswer)
    case score(DecisionScoreAnswer)
    case refusal

    public var isRefusal: Bool { self == .refusal }

    public var probability: Double? {
        guard case .predicate(let probability, _) = self else { return nil }
        return probability
    }
    public var choice: DecisionChoiceAnswer? {
        guard case .choice(let answer) = self else { return nil }
        return answer
    }
    public var score: DecisionScoreAnswer? {
        guard case .score(let answer) = self else { return nil }
        return answer
    }
}

public struct DecisionChoiceAnswer: Equatable, Sendable {
    /// The most likely option value.
    public let choice: String
    public let confidence: Double?
    /// Option value to probability, when the provider returns a distribution.
    public let probabilities: [String: Double]

    public init(choice: String, confidence: Double?, probabilities: [String: Double]) {
        self.choice = choice
        self.confidence = confidence
        self.probabilities = probabilities
    }
}

public struct DecisionScoreAnswer: Equatable, Sendable {
    public struct Level: Equatable, Sendable {
        public let index: Int
        public let label: String
        /// Nil when the provider omitted this level's probability.
        public let probability: Double?

        public init(index: Int, label: String, probability: Double?) {
            self.index = index
            self.label = label
            self.probability = probability
        }
    }

    /// Expected level index (probability-weighted), so it may be fractional.
    public let score: Double
    public let confidence: Double?
    /// One entry per requested level, in request order (the score legend).
    public let levels: [Level]

    public init(score: Double, confidence: Double?, levels: [Level]) {
        self.score = score
        self.confidence = confidence
        self.levels = levels
    }

    /// The level with the highest probability, or the rounded score if none.
    public var mostLikelyLevel: Level? {
        let ranked = levels.filter { $0.probability != nil }
        if let best = ranked.max(by: { ($0.probability ?? 0) < ($1.probability ?? 0) }) { return best }
        let index = Int(score.rounded())
        return levels.indices.contains(index) ? levels[index] : nil
    }
}

public struct DecisionUsage: Equatable, Sendable {
    public let inputTokens: Int
    public let outputTokens: Int
    /// Reported by OpenAI only.
    public let totalTokens: Int?
    public let cachedInputTokens: Int?
    /// OpenRouter's charge in credits.
    public let cost: Double?

    public init(
        inputTokens: Int, outputTokens: Int, totalTokens: Int? = nil,
        cachedInputTokens: Int? = nil, cost: Double? = nil
    ) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.totalTokens = totalTokens
        self.cachedInputTokens = cachedInputTokens
        self.cost = cost
    }
}

// MARK: - Wire formats

/// The HTTP contract an endpoint speaks. Gateways that host Jev (e.g. other
/// System One routes) can reuse `.systemOne` with their own endpoint.
public enum DecisionWireFormat: Sendable {
    /// OpenAI `POST /v1/decisions`: `input`, ordered `questions` array, `predicate`.
    case openAI
    /// TypeSafe System One (also OpenRouter Decisions): `state`, named `questions` map, `noul`.
    case systemOne
}

extension DecisionRequest {
    /// Local checks shared by every provider, plus OpenAI's question limit.
    func validate(for format: DecisionWireFormat) throws {
        guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LLMError.invalidConfiguration("A model ID is required.")
        }
        guard !questions.isEmpty else {
            throw LLMError.invalidConfiguration("A decision request needs at least one question.")
        }
        if format == .openAI, questions.count > 400 {
            throw LLMError.invalidConfiguration("OpenAI accepts at most 400 questions per decision.")
        }
        var names = Set<String>()
        for question in questions {
            let name = question.name
            guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw LLMError.invalidConfiguration("Every decision question needs a name.")
            }
            guard names.insert(name).inserted else {
                throw LLMError.invalidConfiguration("Duplicate decision question name: \(name).")
            }
            switch question.kind {
            case .predicate: break
            case .choice(let options):
                guard (2...255).contains(options.count) else {
                    throw LLMError.invalidConfiguration("Choice question \(name) needs 2 to 255 options.")
                }
                guard Set(options.map(\.value)).count == options.count else {
                    throw LLMError.invalidConfiguration("Choice question \(name) has duplicate options.")
                }
            case .score(let levels):
                guard (2...10).contains(levels.count) else {
                    throw LLMError.invalidConfiguration("Score question \(name) needs 2 to 10 levels.")
                }
                guard Set(levels.map(\.label)).count == levels.count else {
                    throw LLMError.invalidConfiguration("Score question \(name) has duplicate level labels.")
                }
            }
        }
    }

    func body(for format: DecisionWireFormat) throws -> JSONValue {
        switch format {
        case .openAI:
            return .object([
                "model": .string(model),
                "input": .string(try state.text()),
                "questions": .array(questions.map(\.openAIValue)),
            ])
        case .systemOne:
            return .object([
                "model": .string(model),
                "state": state.jsonValue,
                "questions": .object(Dictionary(uniqueKeysWithValues: questions.map { ($0.name, $0.systemOneValue) })),
            ])
        }
    }
}

extension DecisionState {
    func text() throws -> String {
        switch self {
        case .text(let text): return text
        case .json(let value):
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            return String(decoding: try encoder.encode(value), as: UTF8.self)
        }
    }

    var jsonValue: JSONValue {
        switch self {
        case .text(let text): .string(text)
        case .json(let value): value
        }
    }
}

extension DecisionQuestion {
    var openAIValue: JSONValue {
        var fields: [String: JSONValue] = ["name": .string(name)]
        switch kind {
        case .predicate(let whenTrue, let whenFalse):
            var text = instructions
            if let whenTrue { text += "\nAnswer true when: \(whenTrue)" }
            if let whenFalse { text += "\nAnswer false when: \(whenFalse)" }
            fields["type"] = .string("predicate")
            fields["instructions"] = .string(text)
        case .choice(let options):
            fields["type"] = .string("choice")
            fields["instructions"] = .string(instructions)
            fields["choices"] = .array(options.map { option in
                var choice: [String: JSONValue] = ["value": .string(option.value)]
                choice["description"] = option.description.map(JSONValue.string)
                return .object(choice)
            })
        case .score(let levels):
            fields["type"] = .string("score")
            fields["instructions"] = .string(instructions)
            fields["levels"] = .array(levels.map { level in
                var entry: [String: JSONValue] = ["label": .string(level.label)]
                entry["description"] = level.description.map(JSONValue.string)
                return .object(entry)
            })
        }
        return .object(fields)
    }

    var systemOneValue: JSONValue {
        var fields: [String: JSONValue] = ["instructions": .string(instructions)]
        switch kind {
        case .predicate(let whenTrue, let whenFalse):
            fields["type"] = .string("noul")
            var criteria: [String: JSONValue] = [:]
            criteria["true"] = whenTrue.map(JSONValue.string)
            criteria["false"] = whenFalse.map(JSONValue.string)
            if !criteria.isEmpty { fields["criteria"] = .object(criteria) }
        case .choice(let options):
            fields["type"] = .string("choice")
            fields["criteria"] = .object(Dictionary(uniqueKeysWithValues: options.map {
                ($0.value, $0.description.map(JSONValue.string) ?? .null)
            }))
        case .score(let levels):
            // Criteria are ordered descriptions; the label is restored locally from the index.
            fields["type"] = .string("score")
            fields["criteria"] = .array(levels.map { level in
                .string(level.description.map { "\(level.label): \($0)" } ?? level.label)
            })
        }
        return .object(fields)
    }
}

// MARK: - Response parsing

enum DecisionResponseParser {
    static func parse(_ data: Data, for request: DecisionRequest, format: DecisionWireFormat) throws -> DecisionResponse {
        let raw = try JSONDecoder().decode(JSONValue.self, from: data)
        guard let root = raw.object, let model = root["model"]?.string else {
            throw LLMError.invalidResponse("The decision response is missing its model.")
        }
        var answers: [String: DecisionAnswer] = [:]
        switch format {
        case .openAI:
            // Answers arrive in question order; names, when present, must agree.
            guard let list = root["answers"]?.array, list.count == request.questions.count else {
                throw LLMError.invalidResponse("Expected one decision answer per question.")
            }
            for (question, value) in zip(request.questions, list) {
                guard let answer = value.object else {
                    throw LLMError.invalidResponse("Decision answer for \(question.name) is not an object.")
                }
                if let name = answer["name"]?.string, name != question.name {
                    throw LLMError.invalidResponse("Decision answer \(name) does not match question \(question.name).")
                }
                answers[question.name] = try parseAnswer(answer, for: question, format: format)
            }
        case .systemOne:
            guard let map = root["answers"]?.object else {
                throw LLMError.invalidResponse("The decision response is missing its answers.")
            }
            for question in request.questions {
                guard let answer = map[question.name]?.object else {
                    throw LLMError.invalidResponse("No decision answer was returned for \(question.name).")
                }
                answers[question.name] = try parseAnswer(answer, for: question, format: format)
            }
        }
        return DecisionResponse(
            id: root["id"]?.string, model: model, provider: root["provider"]?.string,
            answers: answers, usage: parseUsage(root["usage"]?.object), raw: raw
        )
    }

    private static func parseAnswer(
        _ answer: [String: JSONValue], for question: DecisionQuestion, format: DecisionWireFormat
    ) throws -> DecisionAnswer {
        let name = question.name
        let type = answer["type"]?.string
        if type == "refusal" { return .refusal }
        let confidence = try optionalProbability(answer["confidence"], name: name)
        switch (question.kind, type) {
        case (.predicate, "predicate"), (.predicate, "noul"):
            let key = format == .openAI ? "probability" : "noul"
            return .predicate(probability: try probability(answer[key], name: name), confidence: confidence)

        case (.choice(let options), "choice"):
            guard let choice = answer["choice"]?.string, options.contains(where: { $0.value == choice }) else {
                throw LLMError.invalidResponse("Decision answer \(name) did not select a requested option.")
            }
            var probabilities: [String: Double] = [:]
            switch answer["probabilities"] {
            case .array(let entries)?: // OpenAI: [{value, probability}]
                for entry in entries {
                    guard let value = entry.object?["value"]?.string else { continue }
                    probabilities[value] = try probability(entry.object?["probability"], name: name)
                }
            case .object(let map)?: // System One: {option: probability}
                for (value, p) in map { probabilities[value] = try probability(p, name: name) }
            default: break
            }
            return .choice(DecisionChoiceAnswer(choice: choice, confidence: confidence, probabilities: probabilities))

        case (.score(let levels), "score"):
            guard let score = answer["score"]?.double, score.isFinite,
                  score >= 0, score <= Double(levels.count - 1) else {
                throw LLMError.invalidResponse("Decision answer \(name) has an invalid score.")
            }
            var byIndex: [Int: Double] = [:]
            switch answer["probabilities"] {
            case .array(let entries)?: // OpenAI: [{label, probability, value}]
                for entry in entries {
                    guard let fields = entry.object else { continue }
                    let index = fields["label"]?.string.flatMap { label in
                        levels.firstIndex { $0.label == label }
                    } ?? fields["value"]?.double.map { Int($0) }
                    if let index, levels.indices.contains(index) {
                        byIndex[index] = try probability(fields["probability"], name: name)
                    }
                }
            case .object(let map)?: // System One: {"0": probability}
                for (key, p) in map {
                    if let index = Int(key), levels.indices.contains(index) {
                        byIndex[index] = try probability(p, name: name)
                    }
                }
            default: break
            }
            let legend = levels.enumerated().map { index, level in
                DecisionScoreAnswer.Level(index: index, label: level.label, probability: byIndex[index])
            }
            return .score(DecisionScoreAnswer(score: score, confidence: confidence, levels: legend))

        default:
            throw LLMError.invalidResponse(
                "Decision answer \(name) has type \(type ?? "missing"), which does not match its question."
            )
        }
    }

    private static func probability(_ value: JSONValue?, name: String) throws -> Double {
        guard let p = value?.double, p.isFinite, (0...1).contains(p) else {
            throw LLMError.invalidResponse("Decision answer \(name) has an invalid probability.")
        }
        return p
    }

    private static func optionalProbability(_ value: JSONValue?, name: String) throws -> Double? {
        guard let value, value != .null else { return nil }
        return try probability(value, name: name)
    }

    private static func parseUsage(_ usage: [String: JSONValue]?) -> DecisionUsage? {
        guard let usage, let input = usage["input_tokens"]?.double,
              let output = usage["output_tokens"]?.double else { return nil }
        return DecisionUsage(
            inputTokens: Int(input), outputTokens: Int(output),
            totalTokens: usage["total_tokens"]?.double.map { Int($0) },
            cachedInputTokens: usage["input_tokens_details"]?.object?["cached_tokens"]?.double.map { Int($0) },
            cost: usage["cost"]?.double
        )
    }
}

private extension JSONValue {
    var double: Double? {
        switch self {
        case .integer(let value): Double(value)
        case .number(let value): value
        default: nil
        }
    }
}
