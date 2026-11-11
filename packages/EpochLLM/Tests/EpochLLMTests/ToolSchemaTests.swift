import Foundation
import Testing
@testable import EpochLLM

private func encodedTool(_ tool: LLMTool) throws -> [String: JSONValue] {
    try JSONDecoder().decode([String: JSONValue].self, from: JSONEncoder().encode(tool))
}

private let emptyObject = JSONValue.object([
    "type": .string("object"), "properties": .object([:]),
    "required": .array([]), "additionalProperties": .bool(false),
])

@Test func typedSchemaEncodesFixture() throws {
    let tool = try LLMTool(name: "roll_dice", description: "Roll a die.", parameters: LLMToolParameters([
        .required("sides", .integer("Number of faces.", enum: [6, 20])),
        .required("reason", .string("Why the roll is needed.")),
        .required("advantage", .boolean()),
        .required("modifier", .number().nullable),
        .required("stance", .string(enum: ["calm", "reckless"]).nullable),
    ]))
    let fields = try encodedTool(tool)
    #expect(fields["type"] == .string("function"))
    #expect(fields["strict"] == .bool(true))
    #expect(fields["parameters"] == .object([
        "type": .string("object"),
        "properties": .object([
            "sides": .object([
                "type": .string("integer"), "description": .string("Number of faces."),
                "enum": .array([.integer(6), .integer(20)]),
            ]),
            "reason": .object(["type": .string("string"), "description": .string("Why the roll is needed.")]),
            "advantage": .object(["type": .string("boolean")]),
            "modifier": .object(["type": .array([.string("number"), .string("null")])]),
            "stance": .object([
                "type": .array([.string("string"), .string("null")]),
                "enum": .array([.string("calm"), .string("reckless"), .null]),
            ]),
        ]),
        "required": .array(["sides", "reason", "advantage", "modifier", "stance"].map(JSONValue.string)),
        "additionalProperties": .bool(false),
    ]))
    #expect(tool.typedParameters != nil)
}

@Test func strictRulesApplyRecursivelyIncludingArrayItems() throws {
    let tool = try LLMTool(name: "equip", description: "Equip items.", parameters: LLMToolParameters([
        .required("loadout", .object([
            .required("items", .array(of: .object([
                .required("name", .string()),
                .required("slot", .object([.required("hand", .string(enum: ["left", "right"]))]).nullable),
            ]))),
        ])),
    ]))
    let root = try #require(tool.parameters.object)
    let loadout = try #require(root["properties"]?.object?["loadout"]?.object)
    let item = try #require(loadout["properties"]?.object?["items"]?.object?["items"]?.object)
    let slot = try #require(item["properties"]?.object?["slot"]?.object)
    for object in [root, loadout, item, slot] {
        #expect(object["additionalProperties"] == .bool(false))
        let declared = Set(try #require(object["properties"]?.object).keys)
        let required = Set(try #require(object["required"]?.array).compactMap(\.string))
        #expect(declared == required)
    }
    #expect(slot["type"] == .array([.string("object"), .string("null")]))
}

@Test func omittablePropertiesRequireNonStrictTools() throws {
    let parameters = LLMToolParameters([
        .required("target", .string()),
        .omittable("note", .string("Flavor text.")),
    ])
    #expect(throws: LLMToolSchemaError.omittableInStrictMode(path: "parameters.note")) {
        try LLMTool(name: "attack", description: "Attack.", parameters: parameters)
    }
    let tool = try LLMTool(name: "attack", description: "Attack.", parameters: parameters, strict: false)
    let fields = try encodedTool(tool)
    #expect(fields["strict"] == .bool(false))
    let schema = try #require(fields["parameters"]?.object)
    #expect(schema["required"] == .array([.string("target")]))
    #expect(schema["properties"]?.object?.keys.sorted() == ["note", "target"])
    #expect(schema["additionalProperties"] == .bool(false))
}

@Test func zeroArgumentToolsUseAnExplicitEmptyObject() throws {
    let tool = try LLMTool(name: "inventory", description: "List inventory.", parameters: .empty)
    #expect(tool.parameters == emptyObject)
    #expect(try LLMToolParameters.empty.jsonValue(strict: false) == emptyObject)
}

@Test func invalidConstructionIsRejectedLocally() {
    let cases: [(LLMToolParameters, LLMToolSchemaError)] = [
        (.init([.required("", .string())]), .emptyPropertyName(path: "parameters")),
        (.init([.required("a", .string()), .required("a", .integer())]), .duplicateProperty(path: "parameters.a")),
        (.init([.required("a", .string(enum: []))]), .emptyEnum(path: "parameters.a")),
        (.init([.required("a", .integer(enum: [1, 1]))]), .duplicateEnumValue(path: "parameters.a")),
        (.init([.required("list", .array(of: .object([.omittable("x", .boolean())])))]),
         .omittableInStrictMode(path: "parameters.list[].x")),
    ]
    for (parameters, error) in cases {
        #expect(throws: error) { try LLMTool(name: "t", description: "t", parameters: parameters) }
    }
}

@Test func mutationsCannotMakeTypedGuaranteesStale() throws {
    var tool = try LLMTool(name: "attack", description: "Attack.", parameters: LLMToolParameters([
        .omittable("note", .string()),
    ]), strict: false)
    tool.strict = true
    #expect(throws: LLMToolSchemaError.omittableInStrictMode(path: "parameters.note")) { try tool.validate() }
    let service = ResponsesService.openAI(apiKey: "test")
    let request = LLMRequest(model: "test", input: [.message(.user, "Hi")], tools: [tool])
    for streaming in [true, false] {
        #expect(throws: LLMToolSchemaError.self) { try service.makeRequest(request, streaming: streaming) }
    }

    // Assigning raw parameters drops the typed model; raw guarantees apply.
    tool.parameters = emptyObject
    #expect(tool.typedParameters == nil)
    try tool.validate()
}

private final class UnreachableProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable)) }
    override func stopLoading() {}
}

@Test func sendAndStreamRejectInvalidRawRootsBeforeNetwork() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [UnreachableProtocol.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    let invalid = LLMTool(name: "bad", description: "Bad.", parameters: .string("invalid"))
    let request = LLMRequest(model: "test", input: [.message(.user, "Hi")], tools: [invalid])
    for service in [ResponsesService.openAI(apiKey: "test", session: session),
                    ResponsesService.openRouter(apiKey: "test", session: session)] {
        await #expect(throws: LLMToolSchemaError.invalidRawRoot(tool: "bad")) { try await service.send(request) }
        await #expect(throws: LLMToolSchemaError.invalidRawRoot(tool: "bad")) {
            for try await _ in service.stream(request) {}
        }
    }
}

@Test func rawSchemasRemainSourceCompatible() throws {
    let raw = JSONValue.object([
        "type": .string("object"),
        "properties": .object(["sides": .object(["type": .string("integer"), "enum": .array([.integer(20)])])]),
        "required": .array([.string("sides")]), "additionalProperties": .bool(false),
    ])
    var tool = LLMTool(name: "roll_dice", description: "Roll.", parameters: raw)
    try tool.validate()
    #expect(tool.parameters == raw)
    #expect(tool.typedParameters == nil)
    let fields = try encodedTool(tool)
    #expect(Set(fields.keys) == ["type", "name", "description", "parameters", "strict"])
    #expect(fields["parameters"] == raw)

    // The typed builder produces the same wire schema as the hand-written one.
    let typed = try LLMTool(name: "roll_dice", description: "Roll.", parameters: LLMToolParameters([
        .required("sides", .integer(enum: [20])),
    ]))
    #expect(try encodedTool(typed) == fields)

    tool.strict = false
    #expect(try encodedTool(tool)["strict"] == .bool(false))
}

@Test func rawSubschemasPassThroughUnchanged() throws {
    let custom = JSONValue.object(["type": .string("string"), "pattern": .string("^[A-Z]{3}$")])
    let tool = try LLMTool(name: "code", description: "Code.", parameters: LLMToolParameters([
        .required("code", .raw(custom)),
    ]))
    #expect(tool.parameters.object?["properties"]?.object?["code"] == custom)
}
