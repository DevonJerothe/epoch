import Foundation

/// The root of a function tool's parameters. It is always a JSON object, so a
/// typed tool cannot send a non-object root. Use `.empty` for zero-argument tools.
///
/// Rendering always lists every non-omittable property in `required` and sets
/// `additionalProperties: false` on every object, including objects nested in
/// arrays. Rendering is independent of `strict`; strict mode only additionally
/// forbids omittable properties (see `LLMSchema.Property`).
public struct LLMToolParameters: Equatable, Sendable {
    public var properties: [LLMSchema.Property]

    public init(_ properties: [LLMSchema.Property]) {
        self.properties = properties
    }

    /// `{"type":"object","properties":{},"required":[],"additionalProperties":false}`
    public static let empty = Self([])

    /// Checks the schema locally and renders the JSON Schema sent to the provider.
    /// This catches construction mistakes only; it is not a full JSON Schema
    /// validator and cannot guarantee a provider or model accepts the schema.
    public func jsonValue(strict: Bool) throws -> JSONValue {
        try LLMSchema.object(properties).render(strict: strict, path: "parameters")
    }
}

/// A typed JSON Schema value for tool parameters. Build values with the static
/// factories; use `.nullable` for values the model may set to null, and `.raw`
/// as an escape hatch for features this model does not cover.
public struct LLMSchema: Equatable, Sendable {
    indirect enum Kind: Equatable, Sendable {
        case string(enum: [String]?)
        case integer(enum: [Int]?)
        case number
        case boolean
        case array(items: LLMSchema)
        case object([Property])
        case raw(JSONValue)
    }

    var kind: Kind
    public var description: String?
    /// Adds `null` to the allowed types (and to `enum`, when present).
    public var isNullable = false

    public static func string(_ description: String? = nil, enum values: [String]? = nil) -> Self {
        Self(kind: .string(enum: values), description: description)
    }

    public static func integer(_ description: String? = nil, enum values: [Int]? = nil) -> Self {
        Self(kind: .integer(enum: values), description: description)
    }

    public static func number(_ description: String? = nil) -> Self {
        Self(kind: .number, description: description)
    }

    public static func boolean(_ description: String? = nil) -> Self {
        Self(kind: .boolean, description: description)
    }

    public static func array(of items: LLMSchema, description: String? = nil) -> Self {
        Self(kind: .array(items: items), description: description)
    }

    public static func object(_ properties: [Property], description: String? = nil) -> Self {
        Self(kind: .object(properties), description: description)
    }

    /// Inserted unchanged. The SDK neither validates it nor applies strict-mode
    /// `required`/`additionalProperties` inside it; the caller owns its correctness.
    public static func raw(_ schema: JSONValue) -> Self {
        Self(kind: .raw(schema), description: nil)
    }

    /// The value is always present but may be null. In strict mode this is the
    /// way to express an optional value.
    public var nullable: Self {
        var copy = self
        copy.isNullable = true
        return copy
    }

    /// A named object property.
    ///
    /// - `required`: the key is always present in the arguments. Combine with
    ///   `.nullable` to let the model send `null` instead of a value.
    /// - `omittable`: the key may be absent from the arguments. Only valid when
    ///   the tool is non-strict; strict schemas require every key.
    public struct Property: Equatable, Sendable {
        public var name: String
        public var schema: LLMSchema
        public var isOmittable: Bool

        public init(_ name: String, _ schema: LLMSchema, isOmittable: Bool = false) {
            self.name = name
            self.schema = schema
            self.isOmittable = isOmittable
        }

        public static func required(_ name: String, _ schema: LLMSchema) -> Self {
            Self(name, schema)
        }

        public static func omittable(_ name: String, _ schema: LLMSchema) -> Self {
            Self(name, schema, isOmittable: true)
        }
    }

    func render(strict: Bool, path: String) throws -> JSONValue {
        var fields: [String: JSONValue] = [:]
        let baseType: String
        switch kind {
        case .raw(let schema):
            return schema
        case .string(let values):
            baseType = "string"
            if let values {
                try Self.checkEnum(values, path: path)
                fields["enum"] = .array(values.map(JSONValue.string) + (isNullable ? [.null] : []))
            }
        case .integer(let values):
            baseType = "integer"
            if let values {
                try Self.checkEnum(values, path: path)
                fields["enum"] = .array(values.map(JSONValue.integer) + (isNullable ? [.null] : []))
            }
        case .number:
            baseType = "number"
        case .boolean:
            baseType = "boolean"
        case .array(let items):
            baseType = "array"
            fields["items"] = try items.render(strict: strict, path: path + "[]")
        case .object(let properties):
            baseType = "object"
            var rendered: [String: JSONValue] = [:]
            var required: [JSONValue] = []
            for property in properties {
                let propertyPath = path + "." + property.name
                guard !property.name.isEmpty else { throw LLMToolSchemaError.emptyPropertyName(path: path) }
                guard rendered[property.name] == nil else {
                    throw LLMToolSchemaError.duplicateProperty(path: propertyPath)
                }
                if property.isOmittable {
                    // Do not silently promote to required: that would change caller intent.
                    if strict { throw LLMToolSchemaError.omittableInStrictMode(path: propertyPath) }
                } else {
                    required.append(.string(property.name))
                }
                rendered[property.name] = try property.schema.render(strict: strict, path: propertyPath)
            }
            fields["properties"] = .object(rendered)
            fields["required"] = .array(required)
            fields["additionalProperties"] = .bool(false)
        }
        fields["type"] = isNullable ? .array([.string(baseType), .string("null")]) : .string(baseType)
        if let description { fields["description"] = .string(description) }
        return .object(fields)
    }

    private static func checkEnum<T: Hashable>(_ values: [T], path: String) throws {
        guard !values.isEmpty else { throw LLMToolSchemaError.emptyEnum(path: path) }
        guard Set(values).count == values.count else { throw LLMToolSchemaError.duplicateEnumValue(path: path) }
    }
}

/// Local schema errors, thrown before any network I/O. `path` names the
/// offending value, e.g. `parameters.target.items[].name`.
public enum LLMToolSchemaError: Error, LocalizedError, Equatable, Sendable {
    case emptyPropertyName(path: String)
    case duplicateProperty(path: String)
    case omittableInStrictMode(path: String)
    case emptyEnum(path: String)
    case duplicateEnumValue(path: String)
    /// Raw parameters must be a JSON object with `"type": "object"`.
    case invalidRawRoot(tool: String)

    public var errorDescription: String? {
        switch self {
        case .emptyPropertyName(let path):
            "\(path): property names must not be empty."
        case .duplicateProperty(let path):
            "\(path): this property is declared more than once."
        case .omittableInStrictMode(let path):
            "\(path): strict tools require every property. Make it required and .nullable, or create the tool with strict: false."
        case .emptyEnum(let path):
            "\(path): an enum needs at least one value; remove the enum to allow any value."
        case .duplicateEnumValue(let path):
            "\(path): enum values must be unique."
        case .invalidRawRoot(let tool):
            "\(tool): tool parameters must be a JSON object schema with \"type\": \"object\". Use LLMToolParameters.empty for zero-argument tools."
        }
    }
}
