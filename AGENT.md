# Project Guidelines

## Organization

- Use `epoch/Feature/<FeatureName>/` for feature-specific code, grouped into `Views`, `ViewModels`, `Models`, and other folders as needed.
- Put reusable code in `epoch/Shared/`, with similar grouping such as `Views`, `Models`, `Services`, and `Managers`.
- Keep related code together; create folders only when needed. This is a folder convention, not a requirement for Clean Architecture layers or protocols.
- Avoid unnecessary file splitting: keep related supporting enums, protocols, structs, and other types in the same file as their primary type (e.g., `FeatureModelEnum` with `FeatureModel`), nesting them when appropriate. Split them out only when the file grows beyond 500 lines or the supporting type has advanced logic.
- Follow this structure for new code; avoid unrelated moves of existing files.

## Swift and SwiftUI

- Use descriptive names: `UpperCamelCase` for types, `lowerCamelCase` for members, and filenames matching their primary type.
- Use four-space indentation, small focused types/functions, and the narrowest practical access control. Prefer `let` and `final` classes where appropriate.
- Keep views focused on presentation; put business logic and side effects in view models, services, or managers.
- Use `@Observable` for shared UI state and view models. Own observable instances with `@State`, inject shared instances through the environment or initializers, and use `@Bindable` when bindings are needed.
- Isolate UI-facing mutable state with `@MainActor`. Prefer structured `async`/`await` and keep blocking work off the main actor.
- Avoid force unwraps, force casts, and `try!`. Use explicit optional handling and propagate recoverable errors.
- Comment intent or non-obvious constraints; avoid narrating obvious code or adding speculative abstractions.

## Navigation

- Route all navigation through [Coordinator.swift](epoch/Core/Navigation/Coordinator.swift), including tabs, pushes, pops, sheets, and dismissals.
- Add routes and navigation actions to the coordinator; views must not own independent navigation paths or routing state.

## UI Design

- Before building or changing UI, read [DESIGN.md](DESIGN.md) for the design rules and token definitions. It takes precedence over visual mockups.
- For component appearance, consult the [Paper direction design sheet](docs/design/Paper%20direction.webp). The older PDFs in `docs/design/` show the retired dark amber direction; do not follow them.
- Use [ThemeManager.swift](epoch/Shared/Managers/ThemeManager.swift) through the SwiftUI environment for design tokens. Apply text styles with `.epochTypography(_:)` so fonts, line spacing, and tracking scale with Dynamic Type. Extend DESIGN.md before introducing new tokens.

## Errors and Logging

- Send every error caught in app code to [ErrorManager.swift](epoch/Shared/Managers/ErrorManager.swift) using `ErrorManager.shared.report(error, context: "Operation description")`.
- Lower-level code and standalone packages should propagate errors to the app boundary for reporting; do not introduce dependencies on app managers into packages.
- Component-specific error messages are allowed, but the underlying error must also reach the error manager. Do not silently discard operational failures with `try?` or empty catches.
- The error manager logs every reported error and shows it as a banner (default) or alert. Pass `presentation: .logOnly` when the call site shows the failure in its own UI, and `retry:` when the operation can be re-run. Recovery actions ("Open Settings", "Try Again") come from `ErrorDescription.describe`; add new error types there.
- Route general logging through [LoggingManager.swift](epoch/Shared/Managers/LoggingManager.swift) (`LoggingManager.shared.info(...)`, `.track(...)` for product events), not `print`. It redacts credentials before any sink sees an entry. Analytics platforms plug in as a `LogSink` added with `addSink(_:)`; do not call a vendor SDK from feature code.

## AI Configuration and Credentials

- Get AI access from [AIConfigurationManager.swift](epoch/Shared/Managers/AIConfigurationManager.swift): `textClient()` and `decisionClient()` each return the configured `EpochAIManager` with that role's model ID, and `generateImage(_:)` covers illustrations. Do not build `EpochLLM` services or read API keys elsewhere.
- Players choose models from the provider's own list (`availableModels(for:)`, shown by `ModelPickerView`); do not add free-text model ID entry. `EpochLLM`'s `ModelCatalogService` documents what each provider's models endpoint reports.
- `saveCredential` checks a key with its provider before storing it; a rejected or uncheckable key is never saved. Do not write to `CredentialStore` directly.
- API keys live only in the Keychain through `CredentialStore`. Never put them in `UserDefaults`, the database, logs, observable state, or tracked files.
- Development builds can use deterministic fixtures with no key and no network: pick "Fixture" in Settings, or launch with `-EpochAIFixtures YES`.

## Working Practices

- Keep changes focused and preserve unrelated work. Update these guidelines concisely as conventions evolve.
- Do not run tests or builds on this machine unless explicitly requested. if tests are run, they should only run for the related changes.
