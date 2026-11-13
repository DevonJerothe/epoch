# EpochLLM

Epoch's Swift package for text generation, RPG function calling, decisions, and image generation. `EpochAIManager` selects between text services accepting `LLMRequest` and returning `LLMResponse`, and independently uses Replicate for images. No dependency on SwiftLLMSDK is required.

OpenAI uses `https://api.openai.com/v1/responses`; OpenRouter uses `https://openrouter.ai/api/v1/responses`. Both use the same Responses adapter for ordinary and streaming requests. The package requires Swift 6.4, iOS 17+ or macOS 14+.

## Chat and provider selection

```swift
import EpochLLM

let manager = EpochAIManager(service: ResponsesService.openAI(apiKey: openAIKey))
await manager.register(ResponsesService.openRouter(apiKey: openRouterKey, appName: "Epoch"))

var request = LLMRequest(
    model: openAIModelID,
    input: [.message(.user, "I approach the ruined tower.")],
    instructions: "You are Epoch's game master. Describe the scene and await the player's action.",
    maxOutputTokens: 800
)
let response = try await manager.send(request)
print(response.text)

// Keep history in Epoch and submit it explicitly on subsequent turns.
request.append(response)
request.input.append(.message(.user, "I examine the doorway."))
let nextResponse = try await manager.send(request)

// Select the provider for future requests, or override it for one request.
try await manager.select(.openRouter)
let routerRequest = LLMRequest(model: openRouterModelID, input: [.message(.user, "Describe a tavern.")])
let routerResponse = try await manager.send(routerRequest)
let directResponse = try await manager.send(request, using: .openAI)
```

Model IDs belong to the chosen provider. Changing the service does not translate model IDs. Keep encrypted reasoning history with the model/provider that produced it; when changing models or providers, start a new request using portable text history and Epoch's game state. Switching providers does not redirect requests already in flight.

## Image generation

Replicate is the only image provider, and `black-forest-labs/flux-schnell` is the only supported model. Each request generates exactly one image with four inference steps. There is no model override or automatic retry of paid prediction creation.

```swift
let manager = EpochAIManager(
    service: ResponsesService.openAI(apiKey: openAIKey),
    imageService: ReplicateImageService(apiKey: replicateKey)
)
let image = try await manager.generateImage(ImageGenerationRequest(
    prompt: "A moonlit ruined tower in a misty forest, fantasy illustration",
    aspectRatio: .landscape,
    outputFormat: .png
))

// Use this URL for direct display, and persist these bytes for lasting access.
let displayURL = image.imageURL
try image.imageData.write(to: destinationURL)
```

`ImageGenerationRequest` defaults to a square PNG; JPG and WebP are also supported. `ImageGenerationResponse` contains the prediction `id`, `imageURL`, `imageData`, and `outputFormat`. The service downloads the image before returning, so download failures throw rather than returning a response without bytes. Replicate's output URLs are temporary: [API output files are removed after an hour by default](https://replicate.com/docs/topics/predictions/data-retention). Store `imageData` for persistent use.

For an existing manager, call `await manager.configureImageGeneration(ReplicateImageService(apiKey: replicateKey))`. Selecting an OpenAI or OpenRouter text service does not affect image generation. The manager accepts any `EpochImageService`, so an app can supply its own adapter (Epoch uses this for development fixtures); pass `nil` to turn image generation off. The Replicate service can also be used directly with `try await service.generateImage(request)`.

The adapter uses [Replicate's official model prediction endpoint](https://replicate.com/docs/reference/http#models.predictions.create) with `Prefer: wait`, then polls if needed until the prediction succeeds. An output in a still-processing prediction is not treated as a completed result. The default 120-second timeout covers generation, polling, and downloading together. Failed/canceled predictions throw `LLMError.responseFailed`; HTTP errors use `LLMError.http`, retaining Replicate's `detail` and `Retry-After`. Deadline expiry throws `URLError(.timedOut)`; network and decoding errors retain their original types. Cancel the calling task to stop network work and polling. Local cancellation or timeout does not guarantee cancellation of the paid prediction on Replicate.

## RPG tools

Describe tool parameters with `LLMToolParameters` and `LLMSchema`, which render JSON Schema for you. Definitions use the flattened Responses shape (`type`, `name`, `parameters`, `strict`), rather than a Chat Completions `function` wrapper.

```swift
let rollDice = try LLMTool(
    name: "roll_dice",
    description: "Roll a die when the player attempts an uncertain action.",
    parameters: LLMToolParameters([
        .required("sides", .integer("Number of faces on the die.", enum: [20])),
        .required("reason", .string("The action being attempted.").nullable),
    ])
)

struct DiceArguments: Decodable { let sides: Int; let reason: String? }
struct DiceResult: Encodable { let roll: Int }

var turn = LLMRequest(
    model: openAIModelID,
    input: [.message(.user, "I force the tower door open.")],
    tools: [rollDice],
    parallelToolCalls: false
)
let result = try await manager.send(turn, using: .openAI)

// Incomplete output remains available for display, but do not execute its calls.
if result.isComplete {
    // Replay every output item, including encrypted reasoning, before results.
    turn.append(result)
    for call in result.toolCalls {
        guard call.name == "roll_dice" else {
            // Handle unknown calls in the app before continuing the conversation.
            throw LLMError.invalidResponse("Unknown game tool: \(call.name)")
        }
        let arguments = try call.decodeArguments(as: DiceArguments.self)
        guard arguments.sides == 20 else {
            throw LLMError.invalidResponse("Unsupported die")
        }
        let output = DiceResult(roll: Int.random(in: 1...arguments.sides))
        turn.input.append(try .toolResult(callID: call.callID, output: output))
    }
    if !result.toolCalls.isEmpty {
        let narration = try await manager.send(turn, using: .openAI)
        // This response can contain more calls; use the same flow if needed.
        print(narration.text)
    }
}
```

The SDK describes tools and transports calls/results. Epoch owns execution, argument validation, game-state changes, duplicate-call tracking, and limits on tool rounds. Results correlate with `callID`, not the output item's `id`. Handle every call returned in a round before continuing. Function arguments remain a JSON string until decoded into an app type.

Model support for tools and sampling/reasoning options varies; omitted tuning fields use provider defaults.

### Tool parameter schemas

`LLMSchema` covers `.string`, `.integer`, `.number`, `.boolean`, `.array(of:)`, and nested `.object`, each with an optional description. Strings and integers accept `enum:` values. The parameter root is always an object; use `LLMToolParameters.empty` for zero-argument tools.

Every rendered object lists its required properties and sets `additionalProperties: false`, recursively, including objects inside arrays. Strict mode is the default and requires every property to be present:

- **Nullable** (`.required("reason", .string().nullable)`): the key is always sent, and its value may be `null`. This is how strict tools express an optional value. Decode it as a Swift optional.
- **Omittable** (`.omittable("note", .string())`): the key may be absent from the arguments. Only non-strict tools (`strict: false`) allow this. In a strict tool it throws `LLMToolSchemaError.omittableInStrictMode` instead of being quietly made required.

`try LLMTool(..., parameters: LLMToolParameters)` throws `LLMToolSchemaError` with a path such as `parameters.items[].name` for empty or duplicate property names, empty or duplicate enum values, and omittable properties in strict tools. `ResponsesService` calls `tool.validate()` before every `send` and `stream`, so changing `strict` afterwards is re-checked before any network I/O. Assigning `tool.parameters` directly replaces the typed schema with a raw one (`typedParameters` becomes `nil`).

Raw JSON Schema remains available for features the typed model does not cover. Use `LLMTool(name:description:parameters: JSONValue)` for a whole schema, or `.raw(JSONValue)` for one property's schema:

```swift
let lookup = try LLMTool(name: "lookup", description: "Find a location.", parameters: LLMToolParameters([
    .required("code", .raw(.object(["type": .string("string"), "pattern": .string("^[A-Z]{3}$")]))),
]))
```

Raw schemas are only checked locally for an object root with `"type": "object"`. Nested keywords, strict-mode rules inside raw values, and spelling are your responsibility. Neither path is a full JSON Schema validator, and neither can guarantee that a provider or model accepts a schema. Decoding arguments and validating their game meaning remain the app's job.

## Streaming

```swift
let events = try await manager.stream(turn, using: .openAI)
for try await event in events {
    switch event {
    case .textDelta(let text): print(text, terminator: "")
    case .response(let final):
        // Same LLMResponse returned by send(), including all tools and usage.
        if final.isComplete { /* inspect final.toolCalls */ }
    default: break
    }
}
```

Text, refusal, reasoning, output-item, and tool-argument events support live display. Execute tools only from an `isComplete` final response. The final response is authoritative; do not append its text to text already assembled from deltas. Reasoning deltas appear only if the provider emits them (request a reasoning summary where supported).

Cancel the task consuming the stream to cancel its network work. Each stream owns its request and finishes after the terminal response. Network failures, failed model responses, malformed known events, and streams ending without a terminal response throw. An `incomplete` response is returned with `incompleteDetails` so the app can handle output limits without losing partial narration. Unknown stream event types are ignored.

## Decisions

Decision APIs answer classification and scoring questions about a shared state, returning probabilities instead of generated text. `DecisionService` supports three providers with one Swift request/response model:

| Option | Factory | Endpoint | Example model | Status |
| --- | --- | --- | --- | --- |
| OpenAI Decisions | `DecisionService.openAI(apiKey:)` | `POST https://api.openai.com/v1/decisions` | `gpt-6-luna` | Public beta |
| OpenRouter Decisions | `DecisionService.openRouter(apiKey:appURL:appName:)` | `POST https://openrouter.ai/api/alpha/decisions` | `typesafe/jev-1.13` | Alpha |
| Jev (TypeSafe direct) | `DecisionService.jev(apiKey:)` | `POST https://api.typesafe.ai/v1/systemone` | `jev-latest` | Direct API |

Each question has a unique `name`; answers are keyed by it. Three question kinds map to each provider's wire format:

- `.predicate(name, instructions, whenTrue:whenFalse:)` → OpenAI `predicate` / TypeSafe `noul`. Returns the probability the statement is true. TypeSafe receives `whenTrue`/`whenFalse` as `criteria`; OpenAI has no criteria field, so they are appended to its instructions.
- `.choice(name, instructions, options:)` → 2–255 unique options, each with an optional description. Returns the chosen option, its confidence, and the probability of every option.
- `.score(name, instructions, levels:)` → 2–10 ordered levels, lowest first. Returns the expected level index (fractional), confidence, and each level's probability as a legend in request order.

`DecisionState` is `.text(String)` or `.json(JSONValue)`; `try .encoding(gameSnapshot)` converts any `Encodable`. OpenRouter and Jev receive JSON state as-is; OpenAI receives it as compact JSON text.

### OpenAI

```swift
let openAI = DecisionService.openAI(apiKey: openAIKey)
let decision = try await openAI.decide(DecisionRequest(
    model: "gpt-6-luna",
    state: .text("The player draws a dagger and steps toward the innkeeper."),
    questions: [
        .predicate("is_hostile", "Is the player acting with hostile intent?"),
        .choice("intent", "What is the player trying to do?", options: [
            "fight", DecisionOption("intimidate", description: "Threaten without attacking"), "trade",
        ]),
        .score("tension", "How tense is the scene?", levels: ["calm", "uneasy", "violent"]),
    ]
))
if let hostile = decision["is_hostile"]?.probability, hostile > 0.8 { /* start combat */ }
```

### OpenRouter

```swift
let openRouter = DecisionService.openRouter(apiKey: openRouterKey, appName: "Epoch")
let routed = try await openRouter.decide(DecisionRequest(
    model: "typesafe/jev-1.13",
    state: try .encoding(sceneSnapshot), // any Encodable game state
    questions: [.predicate("is_bug", "Is this a bug report?", whenTrue: "Something is broken", whenFalse: "A question or request")]
))
print(routed.id ?? "", routed.provider ?? "", routed.usage?.cost ?? 0)
```

OpenRouter adds `id`, `provider`, and `usage.cost`, which `DecisionResponse` exposes. It is an alpha route; its shape may change.

### Jev (TypeSafe)

```swift
let jev = DecisionService.jev(apiKey: typeSafeKey)
let answer = try await jev.decide(DecisionRequest(
    model: "jev-latest",
    state: .text("I was charged twice for my subscription."),
    questions: [.choice("department", "Which team should handle this?", options: ["billing", "technical", "sales"])]
))
switch answer["department"] {
case .choice(let result)?: print(result.choice, result.confidence ?? 0, result.probabilities)
case .refusal?: print("Declined")
default: break
}
print(answer.model) // The resolved version, e.g. jev-1.13.0, can differ from the alias.
```

### Selecting a provider and handling errors

```swift
let manager = EpochAIManager(service: ResponsesService.openAI(apiKey: openAIKey), decisionService: DecisionService.jev(apiKey: typeSafeKey))
await manager.registerDecisionService(DecisionService.openRouter(apiKey: openRouterKey))
try await manager.selectDecisionService(.openRouter)          // affects future decide() calls
let result = try await manager.decide(request)                // uses OpenRouter
let direct = try await manager.decide(jevRequest, using: .jev) // per-request override

do {
    _ = try await manager.decide(request)
} catch let error as LLMError where error.isRetryable {
    // 408, 429, 5xx, 524, 529: back off (honor error's retryAfter when present) and retry.
} catch let error as URLError where error.code == .timedOut {
    // The client-side timeoutInterval elapsed: back off and retry like a 408.
} catch let error as LLMError {
    // Local validation (.invalidConfiguration), malformed answers (.invalidResponse), or a non-retryable .http.
}
```

Decision selection is independent of the text service. Model IDs belong to the chosen provider and are never translated. `DecisionResponse` contains `answers`, the resolved `model`, `usage` (input/output tokens, plus `totalTokens`, `cachedInputTokens`, and `cost` where reported), and `raw` for any unmodeled field such as OpenRouter cost details.

Any question can return `.refusal` while the others still answer. Requests are validated locally before network I/O (model, unique names, option/level counts, OpenAI's 400-question limit). A response missing an answer, returning the wrong answer type, choosing an unrequested option, or giving a probability outside 0...1 throws `LLMError.invalidResponse`, as does a body that is not valid JSON or a token count that is not a non-negative whole number. HTTP errors become `LLMError.http`, with the message from OpenAI/OpenRouter `error` bodies or TypeSafe `detail` bodies (422 validation errors read as `body.state: Field required`), plus `Retry-After`. Transport failures keep their `URLError` type, so a client-side timeout is `URLError(.timedOut)` rather than an `LLMError`. The SDK never retries; TypeSafe recommends exponential backoff for 429 and 529.

Not supported yet: image inputs (OpenAI base64 data URLs, TypeSafe/OpenRouter `assets`), TypeSafe `box` questions, OpenRouter provider routing preferences, and OpenAI prompt caching options. Recheck the beta/alpha contracts before relying on them in production.

## Listing models

`ModelCatalogService` fetches the models a provider offers from each provider's own endpoint, so an app can offer a list instead of asking for an ID. Results are `LLMModelInfo` values; only `id` is guaranteed, and other fields are `nil` when the provider does not report them.

```swift
let narrators = try await ModelCatalogService.openRouter(apiKey: openRouterKey).listModels(for: .text)
let arbiters = try await ModelCatalogService.jev(apiKey: typeSafeKey).listModels(for: .decisions)
```

| Provider | Endpoint | Reported | `.text` | `.decisions` |
| --- | --- | --- | --- | --- |
| OpenAI | `GET https://api.openai.com/v1/models` | `id`, `owner`, `released`, `retirementDate` | Models whose ID has none of `openAINonTextModelMarkers` | Models matching `openAIDecisionModelPrefixes` (`gpt-6-luna`) |
| OpenRouter | `GET https://openrouter.ai/api/v1/models` | `name`, `summary`, `contextLength`, `pricing`, `released`, `retirementDate`, `aliasTarget` | `endpoints=/api/v1/responses` | `endpoints=/api/alpha/decisions&output_modalities=decisions` |
| TypeSafe | `GET https://api.typesafe.ai/v1/models` | `summary`, `released` | Throws | The account's Jev aliases |

OpenAI's endpoint has no capability field or filter, so its `.text` list hides models by name (embeddings, audio, images, video, moderation), and its `.decisions` list is narrowed by a constant taken from the Decisions reference. Both are heuristics to revisit as OpenAI's lineup changes. OpenRouter's list is public, so `ModelCatalogService.openRouter()` works without a key. Its prices arrive as USD-per-token strings and are exposed per million tokens; its pages are followed through `links.next`. TypeSafe lists aliases only: versioned IDs such as `jev-1.14.0` are accepted by the API but not listed, and pricing is not in the response. Nothing is cached or retried. Implement `EpochModelCatalog` to supply another source.

## Checking an API key

`APIKeyValidator` asks a provider whether a key works before an app stores it, using one authenticated GET that generates and bills nothing.

```swift
do {
    try await APIKeyValidator(provider: .openRouter).validate(typedKey)
} catch let error as LLMError where error.isRejectedCredential {
    // 401 or 403: the provider refused this key.
} catch {
    // Network or provider trouble: the key was not checked, which is not the same as wrong.
}
```

| Provider | Request |
| --- | --- |
| OpenAI | `GET https://api.openai.com/v1/models` |
| OpenRouter | `GET https://openrouter.ai/api/v1/key` (its models list is public, so it proves nothing) |
| TypeSafe | `GET https://api.typesafe.ai/v1/models` |
| Replicate | `GET https://api.replicate.com/v1/account` |

A key that passes can still fail later for lack of credit or model access.

## Stateless history and errors

`store: false` is enforced for both providers, in both modes. There is no `previous_response_id` or server-side conversation API. Requests include `reasoning.encrypted_content`, and `LLMItem` retains full output JSON for replay. `request.append(response)` adds those items in order. The SDK keeps no conversation state or persistent credential storage.

`LLMResponse` exposes `text`, `refusals`, `toolCalls`, `usage`, `status`, and raw `output` items. `LLMError.http` includes the status, provider message/code, and `Retry-After` header. Network and decoding errors retain their original types. Requests are not automatically retried, since retry policy should account for an RPG turn's tool effects.

## Extending providers / post MVP

Implement the `Sendable` `EpochLLMService` protocol (`id`, `send`, `stream`) and register the adapter on the existing manager. A new Responses-compatible endpoint can reuse `ResponsesService(id:baseURL:apiKey:...)`; injected `URLSession` and headers support configuration and testing.

**LM Studio REST API support is post MVP.** Add a separate adapter translating `LLMRequest` into LM Studio's REST format and its responses/stream into `LLMResponse` / `LLMStreamEvent`. It should maintain stateless requests and map native history/tool data into replayable items without changes to the manager. No LM Studio endpoint or Chat Completions fallback is enabled today.

Built-in hosted tools, automatic tool execution, and automatic retries are outside this MVP. The Xcode project references `packages/EpochLLM` as a local package dependency and links its `EpochLLM` library product to the app target. The package appears under the `packages` group in the project navigator, and its files are tracked by the main project's Git repository.

## Validation and API references

From the project root, run `swift test --package-path packages/EpochLLM`. Tests use an ephemeral URLSession with fixture URLProtocol responses; no keys or paid API calls are needed. They cover both text endpoints, all three decision providers' wire formats, answer parsing, and error normalization, stateless request encoding, full history replay, typed tools and tool parameter schemas, streamed UTF-8 and SSE framing, HTTP/model failures, truncation, provider selection, and custom adapters. Image tests cover the fixed FLUX Schnell request, prediction polling, URL and byte delivery, malformed outputs, download failures, cancellation, and deadlines during creation, polling, and downloading.

- [OpenAI Responses migration and stateless history](https://developers.openai.com/api/docs/guides/migrate-to-responses)
- [OpenAI function calling and streaming](https://developers.openai.com/api/docs/guides/function-calling)
- [OpenRouter Responses API reference](https://openrouter.ai/docs/api/api-reference/responses/create-responses)
- [OpenAI Create a decision](https://developers.openai.com/api/reference/resources/decisions/methods/create)
- [OpenRouter Submit a Decisions request](https://openrouter.ai/docs/api/api-reference/alphadecisions/submit-a-decisions-request)
- [TypeSafe System One HTTP API](https://docs.typesafe.ai/api)
- [Replicate FLUX Schnell schema](https://replicate.com/black-forest-labs/flux-schnell/api/schema)
- [Replicate predictions and polling](https://replicate.com/docs/topics/predictions/create-a-prediction)
