import EpochLLM
import Foundation
import Observation

/// What the player is told about an error, and the one recovery that fits it.
nonisolated struct ErrorDescription: Equatable, Sendable {
    enum Recovery: Equatable, Sendable {
        /// The fix is in Settings: a missing or rejected key, or a bad provider or model.
        case openSettings
        /// The same operation may succeed if tried again.
        case retry
        case none
    }

    var title: String
    var message: String
    var recovery: Recovery

    /// `nil` for cancellations, which are not failures and are never shown.
    static func describe(_ error: any Error) -> ErrorDescription? {
        switch error {
        case is CancellationError:
            nil
        case let error as AIConfigurationError:
            ErrorDescription(
                title: error.title, message: error.localizedDescription,
                recovery: error.isEntryProblem ? .none : .openSettings
            )
        case let error as LLMError:
            describe(error)
        case let error as URLError:
            describe(error)
        case let error as KeychainError:
            ErrorDescription(title: "Keychain unavailable", message: error.localizedDescription, recovery: .retry)
        case let error as AppDBError:
            ErrorDescription(title: "Database problem", message: error.localizedDescription, recovery: .none)
        default:
            ErrorDescription(title: "Something went wrong", message: error.localizedDescription, recovery: .retry)
        }
    }

    private static func describe(_ error: LLMError) -> ErrorDescription {
        switch error {
        case .unregisteredService:
            return ErrorDescription(
                title: "AI service isn't set up",
                message: "Choose a provider and add its API key in Settings.", recovery: .openSettings
            )
        case .invalidConfiguration(let message):
            return ErrorDescription(title: "AI settings need attention", message: message, recovery: .openSettings)
        case .http(let status, let message, let code, let retryAfter):
            switch status {
            case 401, 403:
                return ErrorDescription(
                    title: "API key rejected",
                    message: "The provider didn't accept this API key. Check or replace it in Settings.",
                    recovery: .openSettings
                )
            case 402:
                return ErrorDescription(
                    title: "Provider account needs attention",
                    message: "The provider reported a billing or credit problem: \(message)", recovery: .retry
                )
            case 404:
                return modelNotFound(message)
            case 429:
                let wait = retryAfter.flatMap { Int($0) }.map { "in \($0) seconds" } ?? "in a moment"
                return ErrorDescription(
                    title: "Too many requests",
                    message: "The provider is rate limiting requests. Try again \(wait).", recovery: .retry
                )
            default:
                if code == "model_not_found" { return modelNotFound(message) }
                if error.isRetryable {
                    return ErrorDescription(
                        title: "Provider unavailable",
                        message: "The provider is having trouble (HTTP \(status)). Try again shortly.",
                        recovery: .retry
                    )
                }
                return ErrorDescription(
                    title: "Request failed",
                    message: "The provider returned an error (HTTP \(status)): \(message)", recovery: .retry
                )
            }
        case .responseFailed(let message, _):
            return ErrorDescription(title: "Response failed", message: message, recovery: .retry)
        case .invalidResponse(let message):
            return ErrorDescription(title: "Unexpected response", message: message, recovery: .retry)
        case .interruptedStream:
            return ErrorDescription(
                title: "Connection interrupted",
                message: "The response stopped before it finished. Try again.", recovery: .retry
            )
        }
    }

    private static func modelNotFound(_ message: String) -> ErrorDescription {
        ErrorDescription(
            title: "Model not found",
            message: "The provider doesn't recognize this model ID. Check it in Settings. (\(message))",
            recovery: .openSettings
        )
    }

    private static func describe(_ error: URLError) -> ErrorDescription? {
        switch error.code {
        case .cancelled:
            nil
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
            ErrorDescription(
                title: "No connection",
                message: "Check your internet connection, then try again.", recovery: .retry
            )
        case .timedOut:
            ErrorDescription(
                title: "Request timed out",
                message: "The provider took too long to answer. Try again.", recovery: .retry
            )
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .secureConnectionFailed:
            ErrorDescription(
                title: "Can't reach the provider",
                message: "Check your internet connection, then try again.", recovery: .retry
            )
        default:
            ErrorDescription(title: "Network problem", message: error.localizedDescription, recovery: .retry)
        }
    }
}

/// An error on screen, with the actions that can recover from it.
struct PresentedError: Identifiable {
    let id = UUID()
    let description: ErrorDescription
    let context: String
    /// Re-runs the failed operation. Offered only when the error is worth retrying.
    let retry: (@MainActor () async -> Void)?

    var title: String { description.title }
    var message: String { description.message }
    var offersSettings: Bool { description.recovery == .openSettings }
    var offersRetry: Bool { description.recovery == .retry && retry != nil }
}

/// Central entry point for error reporting. Every reported error is logged (redacted) through
/// `LoggingManager`, then shown as a banner or alert with a recovery action where one exists.
/// `ErrorPresentation` renders the state published here.
@MainActor
@Observable
final class ErrorManager {
    enum Presentation {
        /// Non-blocking strip at the top of the screen. The default.
        case banner
        /// Blocking alert, for failures the player must acknowledge before continuing.
        case alert
        /// For call sites that already show the failure in their own UI.
        case logOnly
    }

    static let shared = ErrorManager()

    private(set) var latestError: (any Error)?
    private(set) var context: String?
    private(set) var banner: PresentedError?
    private(set) var alert: PresentedError?

    @ObservationIgnored private let logger: LoggingManager

    init(logger: LoggingManager = .shared) {
        self.logger = logger
    }

    /// - Parameters:
    ///   - context: The operation that failed, e.g. "Saving the API key".
    ///   - retry: Re-runs the operation; shown as "Try Again" when the error is retryable.
    func report(
        _ error: any Error, context: String,
        presentation: Presentation = .banner,
        retry: (@MainActor () async -> Void)? = nil
    ) {
        guard var description = ErrorDescription.describe(error) else {
            logger.debug("\(context) was cancelled", category: .error)
            return
        }
        latestError = error
        self.context = context

        let nsError = error as NSError
        logger.error("\(context): \(error.localizedDescription)", category: .error, metadata: [
            "type": String(reflecting: type(of: error)),
            "domain": nsError.domain,
            "code": String(nsError.code),
            "detail": String(describing: error),
        ])

        // Provider messages can echo a key back, so what is shown is redacted too.
        description.message = logger.redactor.redact(description.message)
        let presented = PresentedError(description: description, context: context, retry: retry)
        switch presentation {
        case .banner: banner = presented
        case .alert: alert = presented
        case .logOnly: break
        }
    }

    func dismissBanner() {
        banner = nil
    }

    func dismissAlert() {
        alert = nil
    }

    func clear() {
        latestError = nil
        context = nil
        banner = nil
        alert = nil
    }
}
