import Foundation

/// JSON schemas and opaque provider items without Any or unchecked Sendable.
public enum JSONValue: Codable, Equatable, Sendable {
    case object([String: JSONValue]), array([JSONValue]), string(String)
    case integer(Int), number(Double), bool(Bool), null

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Int.self) { self = .integer(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .integer(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }

    public var string: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    public var object: [String: JSONValue]? {
        guard case .object(let value) = self else { return nil }
        return value
    }

    public var array: [JSONValue]? {
        guard case .array(let value) = self else { return nil }
        return value
    }
}

public enum LLMRole: String, Codable, Sendable {
    case system, developer, user, assistant
}

/// A Responses item. Keeping its complete JSON preserves encrypted reasoning,
/// annotations, and future item types when replaying a stateless conversation.
public struct LLMItem: Codable, Equatable, Sendable {
    public let fields: [String: JSONValue]

    public init(fields: [String: JSONValue]) { self.fields = fields }
    public init(from decoder: Decoder) throws {
        fields = try decoder.singleValueContainer().decode([String: JSONValue].self)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(fields)
    }

    public var type: String? { fields["type"]?.string }

    public static func message(_ role: LLMRole, _ text: String) -> Self {
        Self(fields: ["role": .string(role.rawValue), "content": .string(text)])
    }

    public static func toolResult(callID: String, output: String) -> Self {
        Self(fields: [
            "type": .string("function_call_output"),
            "call_id": .string(callID), "output": .string(output),
        ])
    }

    public static func toolResult<T: Encodable>(callID: String, output: T) throws -> Self {
        let data = try JSONEncoder().encode(output)
        return .toolResult(callID: callID, output: String(decoding: data, as: UTF8.self))
    }

    public var toolCall: LLMToolCall? {
        guard type == "function_call",
              let callID = fields["call_id"]?.string,
              let name = fields["name"]?.string,
              let arguments = fields["arguments"]?.string else { return nil }
        return LLMToolCall(callID: callID, name: name, arguments: arguments)
    }
}

public struct LLMToolCall: Equatable, Sendable {
    /// Correlates a result with a call; this differs from the output item's id.
    public let callID: String
    public let name: String
    public let arguments: String

    public init(callID: String, name: String, arguments: String) {
        self.callID = callID
        self.name = name
        self.arguments = arguments
    }

    public func decodeArguments<T: Decodable>(as type: T.Type = T.self) throws -> T {
        try JSONDecoder().decode(type, from: Data(arguments.utf8))
    }
}

public struct LLMTool: Encodable, Equatable, Sendable {
    public let type = "function"
    public var name: String
    public var description: String
    /// The JSON Schema sent to the provider. Assigning a raw value discards
    /// `typedParameters`, so the tool then has only raw-schema guarantees.
    public var parameters: JSONValue {
        get { renderedParameters }
        set {
            renderedParameters = newValue
            typedParameters = nil
        }
    }
    /// In strict schemas every property must be required and every object must
    /// specify additionalProperties: false. Optional values use a nullable type.
    /// Typed parameters are re-checked against this value by `validate()`.
    public var strict: Bool
    /// Set only for tools built from `LLMToolParameters`.
    public private(set) var typedParameters: LLMToolParameters?
    private var renderedParameters: JSONValue

    /// Raw-schema escape hatch for features `LLMSchema` does not model. Only the
    /// root shape is checked locally (see `validate()`).
    public init(name: String, description: String, parameters: JSONValue, strict: Bool = true) {
        self.name = name
        self.description = description
        self.renderedParameters = parameters
        self.strict = strict
    }

    /// Throws `LLMToolSchemaError` when the schema is contradictory, e.g. an
    /// omittable property in a strict tool.
    public init(
        name: String, description: String, parameters: LLMToolParameters, strict: Bool = true
    ) throws {
        self.name = name
        self.description = description
        self.renderedParameters = try parameters.jsonValue(strict: strict)
        self.strict = strict
        self.typedParameters = parameters
    }

    /// Local checks run before every request. Typed tools are fully re-checked
    /// against the current `strict` value. Raw tools are only checked to have an
    /// object root with `"type": "object"`; nested keywords, strict-mode rules,
    /// and provider/model support are not validated for them.
    public func validate() throws {
        if let typedParameters {
            _ = try typedParameters.jsonValue(strict: strict)
        } else {
            guard renderedParameters.object?["type"] == .string("object") else {
                throw LLMToolSchemaError.invalidRawRoot(tool: name)
            }
        }
    }

    enum CodingKeys: String, CodingKey { case type, name, description, parameters, strict }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(type, forKey: .type)
        try c.encode(name, forKey: .name)
        try c.encode(description, forKey: .description)
        try c.encode(renderedParameters, forKey: .parameters)
        try c.encode(strict, forKey: .strict)
    }
}

public enum LLMToolChoice: Encodable, Equatable, Sendable {
    case auto, none, required, function(name: String)

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .auto: try c.encode("auto")
        case .none: try c.encode("none")
        case .required: try c.encode("required")
        case .function(let name): try c.encode(["type": "function", "name": name])
        }
    }
}
