import Foundation

/// Shared request for chat and function calling. No server-side conversation IDs
/// are used: supply the complete input history for every turn.
public struct LLMRequest: Encodable, Sendable {
    public var model: String
    public var input: [LLMItem]
    public var instructions: String?
    public var tools: [LLMTool]?
    public var toolChoice: LLMToolChoice?
    public var parallelToolCalls: Bool?
    public var maxOutputTokens: Int?
    public var temperature: Double?
    public var topP: Double?
    public var reasoning: LLMReasoning?
    public let store = false
    public let include = ["reasoning.encrypted_content"]

    public init(
        model: String, input: [LLMItem], instructions: String? = nil,
        tools: [LLMTool]? = nil, toolChoice: LLMToolChoice? = nil,
        parallelToolCalls: Bool? = nil, maxOutputTokens: Int? = nil,
        temperature: Double? = nil, topP: Double? = nil, reasoning: LLMReasoning? = nil
    ) {
        self.model = model
        self.input = input
        self.instructions = instructions
        self.tools = tools
        self.toolChoice = toolChoice
        self.parallelToolCalls = parallelToolCalls
        self.maxOutputTokens = maxOutputTokens
        self.temperature = temperature
        self.topP = topP
        self.reasoning = reasoning
    }

    enum CodingKeys: String, CodingKey {
        case model, input, instructions, tools, temperature, reasoning, store, include
        case toolChoice = "tool_choice", parallelToolCalls = "parallel_tool_calls"
        case maxOutputTokens = "max_output_tokens", topP = "top_p"
    }

    /// Append all output items before tool results or the next user message.
    public mutating func append(_ response: LLMResponse) {
        input.append(contentsOf: response.output)
    }
}

public struct LLMReasoning: Encodable, Sendable {
    public var effort: String
    public var summary: String?
    public init(effort: String, summary: String? = nil) {
        self.effort = effort
        self.summary = summary
    }
}

public struct LLMResponse: Codable, Equatable, Sendable {
    public let id: String
    public let model: String
    /// Open-ended for new provider statuses. Incomplete is a valid partial result.
    public let status: String
    public let output: [LLMItem]
    public let usage: LLMUsage?
    public let error: LLMResponseError?
    public let incompleteDetails: JSONValue?

    public init(
        id: String, model: String, status: String, output: [LLMItem],
        usage: LLMUsage? = nil, error: LLMResponseError? = nil, incompleteDetails: JSONValue? = nil
    ) {
        self.id = id
        self.model = model
        self.status = status
        self.output = output
        self.usage = usage
        self.error = error
        self.incompleteDetails = incompleteDetails
    }

    public var text: String {
        content(ofType: "output_text", field: "text").joined()
    }
    public var refusals: [String] { content(ofType: "refusal", field: "refusal") }
    public var toolCalls: [LLMToolCall] { output.compactMap(\.toolCall) }
    public var isComplete: Bool { status == "completed" }

    private func content(ofType type: String, field: String) -> [String] {
        output.filter { $0.type == "message" }.flatMap { item in
            (item.fields["content"]?.array ?? []).compactMap { part in
                guard let object = part.object, object["type"]?.string == type else { return nil }
                return object[field]?.string
            }
        }
    }

    func validated() throws -> Self {
        if status == "failed" || error != nil {
            throw LLMError.responseFailed(
                message: error?.message ?? "Model response failed.", code: error?.code
            )
        }
        guard status == "completed" || status == "incomplete" else {
            throw LLMError.invalidResponse("Unexpected final response status: \(status).")
        }
        for item in output where item.type == "function_call" && item.toolCall == nil {
            throw LLMError.invalidResponse("A function call is missing call_id, name, or arguments.")
        }
        return self
    }

    enum CodingKeys: String, CodingKey {
        case id, model, status, output, usage, error
        case incompleteDetails = "incomplete_details"
    }
}

public struct LLMUsage: Codable, Equatable, Sendable {
    public let inputTokens: Int
    public let outputTokens: Int
    public let totalTokens: Int
    public let inputTokensDetails: JSONValue?
    public let outputTokensDetails: JSONValue?

    public init(
        inputTokens: Int, outputTokens: Int, totalTokens: Int,
        inputTokensDetails: JSONValue? = nil, outputTokensDetails: JSONValue? = nil
    ) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.totalTokens = totalTokens
        self.inputTokensDetails = inputTokensDetails
        self.outputTokensDetails = outputTokensDetails
    }

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens", outputTokens = "output_tokens", totalTokens = "total_tokens"
        case inputTokensDetails = "input_tokens_details", outputTokensDetails = "output_tokens_details"
    }
}

public struct LLMResponseError: Codable, Equatable, Sendable {
    public let message: String
    // OpenRouter can return numeric error codes; normalize to a string.
    public let code: String?

    public init(message: String, code: String? = nil) {
        self.message = message
        self.code = code
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        message = try c.decode(String.self, forKey: .message)
        let raw = try c.decodeIfPresent(JSONValue.self, forKey: .code)
        switch raw {
        case .string(let value): code = value
        case .integer(let value): code = String(value)
        default: code = nil
        }
    }
    enum CodingKeys: String, CodingKey { case message, code }
}

/// Deltas are display-only. Execute calls from a complete final response so
/// partial arguments or interrupted streams cannot mutate RPG state.
public enum LLMStreamEvent: Equatable, Sendable {
    case textDelta(String)
    case reasoningDelta(String)
    case refusalDelta(String)
    case outputItemAdded(index: Int, item: LLMItem)
    case toolArgumentsDelta(index: Int, itemID: String, delta: String)
    case response(LLMResponse)
}
