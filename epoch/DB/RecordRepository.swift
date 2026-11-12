import Foundation
import GRDB

/// CRUD for every Epoch table. Models expose `record` and `init(record:)` for conversion.
/// Calls suspend the caller while the work runs on the database queue.
nonisolated struct RecordRepository<Record: EpochRecord>: Sendable {
    let database: DBManager

    init(database: DBManager) {
        self.database = database
    }

    @MainActor
    init() {
        self.init(database: .shared)
    }

    func getAll() async throws -> [Record] {
        try await database.read { db in
            try Record.order(Column("createdAt"), Column("id")).fetchAll(db)
        }
    }

    func get(id: UUID) async throws -> Record? {
        try await database.read { db in
            // UUID query values otherwise use GRDB's default blob representation.
            try Record.filter(Column("id") == id.uuidString).fetchOne(db)
        }
    }

    @discardableResult
    func save(_ record: Record) async throws -> Record {
        var updated = record
        updated.updatedAt = .now
        // An immutable copy, so the Sendable database closure captures no mutable state.
        let saved = updated
        try await database.write { db in try saved.save(db) }
        return saved
    }

    @discardableResult
    func delete(id: UUID) async throws -> Bool {
        try await database.write { db in
            try Record.filter(Column("id") == id.uuidString).deleteAll(db) > 0
        }
    }
}
