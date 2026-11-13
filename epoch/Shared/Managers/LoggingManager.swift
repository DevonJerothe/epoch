import Foundation
import os

nonisolated enum LogLevel: Int, Comparable, Sendable {
    case debug, info, warning, error

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Open-ended so features can add their own categories.
nonisolated struct LogCategory: RawRepresentable, Hashable, Sendable {
    let rawValue: String

    static let app = Self(rawValue: "app")
    static let error = Self(rawValue: "error")
    static let ai = Self(rawValue: "ai")
    static let settings = Self(rawValue: "settings")
    /// Product events from `LoggingManager.track`. An analytics sink can forward only these.
    static let analytics = Self(rawValue: "analytics")
}

/// What a sink receives. `message` and `metadata` values are already redacted.
nonisolated struct LogEntry: Equatable, Sendable {
    let date: Date
    let level: LogLevel
    let category: LogCategory
    let message: String
    let metadata: [String: String]
}

/// A destination for log entries. To add a platform such as PostHog, conform a type to this
/// and pass it to `LoggingManager.shared.addSink(_:)` at launch; no call sites change.
nonisolated protocol LogSink: Sendable {
    func record(_ entry: LogEntry)
}

/// Writes to the unified system log. Values are private, so they show in Xcode but not in sysdiagnoses.
nonisolated struct OSLogSink: LogSink {
    private let subsystem: String

    init(subsystem: String = Bundle.main.bundleIdentifier ?? "epoch") {
        self.subsystem = subsystem
    }

    func record(_ entry: LogEntry) {
        let details = entry.metadata.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        let text = details.isEmpty ? entry.message : "\(entry.message) [\(details)]"
        let type: OSLogType = switch entry.level {
        case .debug: .debug
        case .info: .info
        case .warning: .default
        case .error: .error
        }
        Logger(subsystem: subsystem, category: entry.category.rawValue)
            .log(level: type, "\(text, privacy: .private)")
    }
}

/// Removes credentials from text before it is logged or shown. It knows the exact secrets the
/// app has handled and also matches common key shapes, so a key that was never registered
/// (e.g. one echoed back in a provider error) is still caught.
nonisolated final class LogRedactor: Sendable {
    static let placeholder = "[REDACTED]"

    /// Shorter values are ignored: redacting them would mangle ordinary words.
    private static let minimumSecretLength = 8

    private static let patterns: [(expression: NSRegularExpression, template: String)] = {
        let sources: [(String, String)] = [
            (#"(?i)\bbearer\s+[A-Za-z0-9._~+/=-]+"#, "Bearer \(placeholder)"),
            // OpenAI (sk-, sk-proj-) and OpenRouter (sk-or-v1-) keys.
            (#"\b(?:sk|pk|rk)-[A-Za-z0-9_-]{8,}"#, placeholder),
            // Replicate tokens.
            (#"\br8_[A-Za-z0-9]{8,}"#, placeholder),
            (#"(?i)((?:api[_-]?key|authorization|token|secret|password)["']?\s*[:=]\s*["']?)[^\s"',;&]+"#,
             "$1\(placeholder)"),
        ]
        return sources.compactMap { source, template in
            // The patterns are literals, so a failure here is a programming error that tests catch.
            (try? NSRegularExpression(pattern: source)).map { ($0, template) }
        }
    }()

    private let secrets = OSAllocatedUnfairLock(initialState: Set<String>())

    /// Remembers a secret so every later occurrence is redacted, whatever its format.
    func register(_ secret: String) {
        let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= Self.minimumSecretLength else { return }
        secrets.withLock { _ = $0.insert(trimmed) }
    }

    func redact(_ text: String) -> String {
        var result = text
        // Longest first, so a secret containing another is replaced whole.
        let known = secrets.withLock { Array($0) }.sorted { $0.count > $1.count }
        for secret in known {
            result = result.replacingOccurrences(of: secret, with: Self.placeholder)
        }
        for (expression, template) in Self.patterns {
            let range = NSRange(result.startIndex..., in: result)
            result = expression.stringByReplacingMatches(in: result, range: range, withTemplate: template)
        }
        return result
    }
}

/// The single entry point for logging. Use it instead of `print`. Callable from any isolation.
/// Every entry is redacted before it reaches a sink.
nonisolated final class LoggingManager: Sendable {
    static let shared = LoggingManager(sinks: [OSLogSink()])

    let redactor: LogRedactor
    private let sinks: OSAllocatedUnfairLock<[any LogSink]>

    init(sinks: [any LogSink] = [], redactor: LogRedactor = LogRedactor()) {
        self.sinks = OSAllocatedUnfairLock(initialState: sinks)
        self.redactor = redactor
    }

    func addSink(_ sink: any LogSink) {
        sinks.withLock { $0.append(sink) }
    }

    func log(
        _ level: LogLevel, _ message: String,
        category: LogCategory = .app, metadata: [String: String] = [:]
    ) {
        let entry = LogEntry(
            date: Date(), level: level, category: category,
            message: redactor.redact(message),
            metadata: metadata.mapValues { redactor.redact($0) }
        )
        for sink in sinks.withLock({ $0 }) { sink.record(entry) }
    }

    func debug(_ message: String, category: LogCategory = .app, metadata: [String: String] = [:]) {
        log(.debug, message, category: category, metadata: metadata)
    }

    func info(_ message: String, category: LogCategory = .app, metadata: [String: String] = [:]) {
        log(.info, message, category: category, metadata: metadata)
    }

    func warning(_ message: String, category: LogCategory = .app, metadata: [String: String] = [:]) {
        log(.warning, message, category: category, metadata: metadata)
    }

    func error(_ message: String, category: LogCategory = .app, metadata: [String: String] = [:]) {
        log(.error, message, category: category, metadata: metadata)
    }

    /// A product event, e.g. `track("story_started")`. Logged under `.analytics`.
    func track(_ event: String, properties: [String: String] = [:]) {
        log(.info, event, category: .analytics, metadata: properties)
    }
}
