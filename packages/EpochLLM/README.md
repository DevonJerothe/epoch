# EpochLLM

Epoch's Swift package for text generation, RPG function calling, and image generation. `EpochAIManager` selects between text services accepting `LLMRequest` and returning `LLMResponse`, and independently uses Replicate for images. No dependency on SwiftLLMSDK is required.

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

For an existing manager, call `await manager.configureImageGeneration(ReplicateImageService(apiKey: replicateKey))`. Selecting an OpenAI or OpenRouter text service does not affect image generation. The Replicate service can also be used directly with `try await service.generateImage(request)`.

The adapter uses [Replicate's official model prediction endpoint](https://replicate.com/docs/reference/http#models.predictions.create) with `Prefer: wait`, then polls if needed until the prediction succeeds. An output in a still-processing prediction is not treated as a completed result. The default 120-second timeout covers generation, polling, and downloading together. Failed/canceled predictions throw `LLMError.responseFailed`; HTTP errors use `LLMError.http`, retaining Replicate's `detail` and `Retry-After`. Deadline expiry throws `URLError(.timedOut)`; network and decoding errors retain their original types. Cancel the calling task to stop network work and polling. Local cancellation or timeout does not guarantee cancellation of the paid prediction on Replicate.

## RPG tools

Use function definitions with JSON Schema. Definitions use the flattened Responses shape (`type`, `name`, `parameters`, `strict`), rather than a Chat Completions `function` wrapper.

```swift
let rollDice = LLMTool(
    name: "roll_dice",
    description: "Roll a die when the player attempts an uncertain action.",
    parameters: .object([
        "type": .string("object"),
        "properties": .object([
            "sides": .object(["type": .string("integer"), "enum": .array([.integer(20)])])
        ]),
        "required": .array([.string("sides")]),
        "additionalProperties": .bool(false)
    ])
)

struct DiceArguments: Decodable { let sides: Int }
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

Strict schemas are enabled by default. Every object must set `additionalProperties: false`, and every property must be required (use nullable types for optional values). Use `strict: false` explicitly for a non-strict schema. Model support for tools and sampling/reasoning options varies; omitted tuning fields use provider defaults.

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

## Stateless history and errors

`store: false` is enforced for both providers, in both modes. There is no `previous_response_id` or server-side conversation API. Requests include `reasoning.encrypted_content`, and `LLMItem` retains full output JSON for replay. `request.append(response)` adds those items in order. The SDK keeps no conversation state or persistent credential storage.

`LLMResponse` exposes `text`, `refusals`, `toolCalls`, `usage`, `status`, and raw `output` items. `LLMError.http` includes the status, provider message/code, and `Retry-After` header. Network and decoding errors retain their original types. Requests are not automatically retried, since retry policy should account for an RPG turn's tool effects.

## Extending providers / post MVP

Implement the `Sendable` `EpochLLMService` protocol (`id`, `send`, `stream`) and register the adapter on the existing manager. A new Responses-compatible endpoint can reuse `ResponsesService(id:baseURL:apiKey:...)`; injected `URLSession` and headers support configuration and testing.

**LM Studio REST API support is post MVP.** Add a separate adapter translating `LLMRequest` into LM Studio's REST format and its responses/stream into `LLMResponse` / `LLMStreamEvent`. It should maintain stateless requests and map native history/tool data into replayable items without changes to the manager. No LM Studio endpoint or Chat Completions fallback is enabled today.

Built-in hosted tools, model discovery, automatic tool execution, and automatic retries are outside this MVP. The Xcode project references `packages/EpochLLM` as a local package dependency and links its `EpochLLM` library product to the app target. The package appears under the `packages` group in the project navigator, and its files are tracked by the main project's Git repository.

## Validation and API references

From the project root, run `swift test --package-path packages/EpochLLM`. Tests use an ephemeral URLSession with fixture URLProtocol responses; no keys or paid API calls are needed. They cover both text endpoints, stateless request encoding, full history replay, typed tools, streamed UTF-8 and SSE framing, HTTP/model failures, truncation, provider selection, and custom adapters. Image tests cover the fixed FLUX Schnell request, prediction polling, URL and byte delivery, malformed outputs, download failures, cancellation, and deadlines during creation, polling, and downloading.

- [OpenAI Responses migration and stateless history](https://developers.openai.com/api/docs/guides/migrate-to-responses)
- [OpenAI function calling and streaming](https://developers.openai.com/api/docs/guides/function-calling)
- [OpenRouter Responses API reference](https://openrouter.ai/docs/api/api-reference/responses/create-responses)
- [Replicate FLUX Schnell schema](https://replicate.com/black-forest-labs/flux-schnell/api/schema)
- [Replicate predictions and polling](https://replicate.com/docs/topics/predictions/create-a-prediction)
