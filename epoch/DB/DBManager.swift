import Foundation
import GRDB
import Observation

/// A Sendable handle to an opened, migrated database. The queue never leaves this type;
/// `Database` and `Row` values must stay inside the read/write closures.
nonisolated struct AppDatabase: Sendable {
    private let queue: DatabaseQueue

    /// Opens the app's on-device database in the documents directory.
    @concurrent
    static func openDefault() async throws -> AppDatabase {
        dispatchPrecondition(condition: .notOnQueue(.main))
        let directory = URL.documentsDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return try await open(path: directory.appending(path: "epoch.sqlite").path)
    }

    /// Opens, configures, and migrates a database. `@concurrent` keeps this blocking work off
    /// the caller's actor. Use ":memory:" for isolated tests and previews.
    @concurrent
    static func open(path: String) async throws -> AppDatabase {
        // Opening and migrating block; trap in debug and tests if this ever lands on the main thread.
        dispatchPrecondition(condition: .notOnQueue(.main))
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA journal_mode = WAL")
        }
        let queue = try DatabaseQueue(path: path, configuration: configuration)
        try DatabaseMigrations.migrator().migrate(queue)
        return AppDatabase(queue: queue)
    }

    /// Suspends the caller while the closure runs on the database queue in one consistent snapshot.
    func read<T: Sendable>(_ block: @Sendable (Database) throws -> T) async throws -> T {
        try await queue.read(block)
    }

    /// GRDB wraps each write in a transaction and rolls back the complete operation on failure.
    func write<T: Sendable>(_ block: @Sendable (Database) throws -> T) async throws -> T {
        try await queue.write(block)
    }
}

/// Owns the database startup lifecycle and publishes its state to the UI.
/// Database work itself runs off the main actor; callers only suspend.
@MainActor
@Observable
final class DBManager {
    enum State: Equatable {
        case loading
        case ready
        case failed(AppDBError)
    }

    typealias Opener = @Sendable () async throws -> AppDatabase

    /// Creating the shared manager does no database work; call `start()` to open it.
    static let shared = DBManager()

    private(set) var state: State = .loading
    @ObservationIgnored private var database: AppDatabase?
    @ObservationIgnored private var startupTask: Task<Void, Never>?
    @ObservationIgnored private let open: Opener

    var startUpError: AppDBError? {
        if case .failed(let error) = state { error } else { nil }
    }

    /// `open` must do its work off the main actor, as `AppDatabase.open(path:)` does.
    init(open: @escaping Opener = { try await AppDatabase.openDefault() }) {
        self.open = open
    }

    /// An already-started database for tests, previews, and imports. Use ":memory:" for isolated tests.
    convenience init(path: String) async throws {
        let opened = try await AppDatabase.open(path: path)
        self.init(open: { opened })
        database = opened
        state = .ready
    }

    /// Opens and migrates the database, or retries after a failure. Safe to call repeatedly:
    /// a ready database is left alone and overlapping calls join the attempt in flight.
    func start() async {
        guard database == nil else { return }
        if let startupTask {
            await startupTask.value
            return
        }
        state = .loading
        // Unstructured so a cancelled caller (e.g. a disappearing view) cannot abort startup.
        let task = Task { await runStartup() }
        startupTask = task
        await task.value
    }

    private func runStartup() async {
        do {
            database = try await open()
            state = .ready
        } catch {
            // The app root shows its own failure screen with Retry, so a banner would repeat it.
            ErrorManager.shared.report(error, context: "Database startup", presentation: .logOnly)
            state = .failed(.startupFailed(error.localizedDescription))
        }
        startupTask = nil
    }

    func read<T: Sendable>(_ block: @Sendable (Database) throws -> T) async throws -> T {
        try await readyDatabase().read(block)
    }

    /// GRDB wraps each write in a transaction and rolls back the complete operation on failure.
    func write<T: Sendable>(_ block: @Sendable (Database) throws -> T) async throws -> T {
        try await readyDatabase().write(block)
    }

    private func readyDatabase() throws -> AppDatabase {
        guard let database else { throw startUpError ?? .unavailable }
        return database
    }
}
