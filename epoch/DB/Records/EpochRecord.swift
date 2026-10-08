import Foundation
import GRDB

nonisolated protocol EpochRecord: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable
where ID == UUID {
    var createdAt: Date { get set }
    var updatedAt: Date { get set }
}

extension EpochRecord {
    nonisolated static func databaseUUIDEncodingStrategy(for column: String) -> DatabaseUUIDEncodingStrategy {
        .uppercaseString
    }
}
