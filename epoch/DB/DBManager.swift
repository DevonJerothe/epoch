import Foundation
import GRDB
import Observation

/// Owns the on-device database. Read/write closures must keep database work inside the closure.
@MainActor
@Observable
final class DBManager {
    static let shared = DBManager()

    private(set) var startUpError: AppDBError?
    @ObservationIgnored private var dbQueue: DatabaseQueue?

    private init() {
        setup()
    }

    /// An injectable database for tests, previews, and imports. Use ":memory:" for isolated tests.
    init(path: String) throws {
        dbQueue = try Self.openDatabase(path: path)
    }

    func setup() {
        do {
            let directory = URL.documentsDirectory
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let queue = try Self.openDatabase(path: directory.appending(path: "epoch.sqlite").path)
            dbQueue = queue
            startUpError = nil
        } catch {
            ErrorManager.shared.report(error, context: "Database startup")
            dbQueue = nil
            startUpError = .startupFailed(error.localizedDescription)
        }
    }

    private static func openDatabase(path: String) throws -> DatabaseQueue {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA journal_mode = WAL")
        }
        let queue = try DatabaseQueue(path: path, configuration: configuration)
        try DatabaseMigrations.migrator().migrate(queue)
        return queue
    }

    func read<T>(_ block: (Database) throws -> T) throws -> T {
        guard let dbQueue else { throw startUpError ?? .unavailable }
        return try dbQueue.read(block)
    }

    /// GRDB wraps each write in a transaction and rolls back the complete operation on failure.
    func write<T>(_ block: (Database) throws -> T) throws -> T {
        guard let dbQueue else { throw startUpError ?? .unavailable }
        return try dbQueue.write(block)
    }
}
