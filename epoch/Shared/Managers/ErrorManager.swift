import Foundation
import Observation

/// Central entry point for error reporting and future logging and alert/banner control.
@MainActor
@Observable
final class ErrorManager {
    static let shared = ErrorManager()

    private(set) var latestError: (any Error)?
    private(set) var context: String?

    private init() {}

    func report(_ error: any Error, context: String) {
        latestError = error
        self.context = context
        // TODO: Forward to a logging manager and coordinate alert/banner presentation.
    }

    func clear() {
        latestError = nil
        context = nil
    }
}
