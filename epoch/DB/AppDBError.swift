import Foundation

nonisolated enum AppDBError: LocalizedError {
    case unavailable
    case startupFailed(String)
    case invalidRelationship(String)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "Database is unavailable."
        case .startupFailed(let message):
            "Database startup failed: \(message)"
        case .invalidRelationship(let message):
            "Invalid database relationship: \(message)"
        }
    }
}
