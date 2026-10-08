import Foundation
import GRDB

/// CRUD for every Epoch table. Models expose `record` and `init(record:)` for conversion.
@MainActor
struct RecordRepository<Record: EpochRecord> {
    let database: DBManager

    init(database: DBManager? = nil) {
        self.database = database ?? .shared
    }

    func getAll() throws -> [Record] {
        try database.read { db in
            try Record.order(Column("createdAt"), Column("id")).fetchAll(db)
        }
    }

    func get(id: UUID) throws -> Record? {
        try database.read { db in
            // UUID query values otherwise use GRDB's default blob representation.
            try Record.filter(Column("id") == id.uuidString).fetchOne(db)
        }
    }

    @discardableResult
    func save(_ record: Record) throws -> Record {
        var record = record
        record.updatedAt = .now
        try database.write { db in try record.save(db) }
        return record
    }

    @discardableResult
    func delete(id: UUID) throws -> Bool {
        try database.write { db in
            try Record.filter(Column("id") == id.uuidString).deleteAll(db) > 0
        }
    }
}
