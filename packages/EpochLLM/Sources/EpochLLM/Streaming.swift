import Foundation

/// Byte-based framing preserves blank lines and UTF-8 across network chunks.
/// Supports CRLF, LF, CR, comments, and multiline data fields.
struct ServerSentEventParser {
    private var line = Data()
    private var data = Data()
    private var skipLF = false
    private let limit = 8 * 1_024 * 1_024

    mutating func append(_ byte: UInt8) throws -> Data? {
        if skipLF {
            skipLF = false
            if byte == 10 { return nil }
        }
        if byte == 13 || byte == 10 {
            skipLF = byte == 13
            return consumeLine()
        }
        guard line.count + data.count < limit else {
            throw LLMError.invalidResponse("A streaming event exceeded the size limit.")
        }
        line.append(byte)
        return nil
    }

    mutating func finish() throws -> Data? {
        if !line.isEmpty { _ = consumeLine() }
        return dispatch()
    }

    private mutating func consumeLine() -> Data? {
        defer { line.removeAll(keepingCapacity: true) }
        if line.isEmpty { return dispatch() }
        guard line.starts(with: Data("data:".utf8)) else { return nil }
        var value = line.dropFirst(5)
        if value.first == 32 { value = value.dropFirst() }
        data.append(contentsOf: value)
        data.append(10)
        return nil
    }

    private mutating func dispatch() -> Data? {
        guard !data.isEmpty else { return nil }
        data.removeLast()
        let result = data
        data = Data()
        return result
    }
}

/// Ignore unknown event types, but reject malformed known events and failures.
enum ResponsesStreamDecoder {
    private struct Event: Decodable {
        let type: String
        let delta: String?
        let outputIndex: Int?
        let itemID: String?
        let item: LLMItem?
        let response: LLMResponse?
        let error: LLMResponseError?
        let message: String?
        let code: JSONValue?
        enum CodingKeys: String, CodingKey {
            case type, delta, item, response, error, message, code
            case outputIndex = "output_index", itemID = "item_id"
        }
    }

    static func decode(_ data: Data) throws -> LLMStreamEvent? {
        if data == Data("[DONE]".utf8) { return nil }
        let event = try JSONDecoder().decode(Event.self, from: data)
        switch event.type {
        case "response.output_text.delta": return .textDelta(try required(event.delta))
        case "response.reasoning_summary_text.delta", "response.reasoning_text.delta":
            return .reasoningDelta(try required(event.delta))
        case "response.refusal.delta": return .refusalDelta(try required(event.delta))
        case "response.output_item.added":
            return .outputItemAdded(index: try required(event.outputIndex), item: try required(event.item))
        case "response.function_call_arguments.delta":
            return .toolArgumentsDelta(
                index: try required(event.outputIndex), itemID: try required(event.itemID),
                delta: try required(event.delta)
            )
        case "response.completed", "response.incomplete":
            return .response(try required(event.response).validated())
        case "response.failed":
            let response = try required(event.response)
            throw LLMError.responseFailed(
                message: response.error?.message ?? "Model response failed.", code: response.error?.code
            )
        case "error":
            let code: String?
            switch event.code {
            case .string(let value): code = value
            case .integer(let value): code = String(value)
            default: code = event.error?.code
            }
            throw LLMError.responseFailed(
                message: event.error?.message ?? event.message ?? "The provider reported a streaming error.",
                code: code
            )
        default: return nil
        }
    }

    private static func required<T>(_ value: T?) throws -> T {
        guard let value else { throw LLMError.invalidResponse("A streaming event is missing a required field.") }
        return value
    }
}
