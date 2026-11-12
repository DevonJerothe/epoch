import Foundation
import GRDB

/// Calls suspend the caller while the work runs on the database queue.
nonisolated struct StoryRepository: Sendable {
    let database: DBManager

    init(database: DBManager) {
        self.database = database
    }

    @MainActor
    init() {
        self.init(database: .shared)
    }

    func getAll() async throws -> [StoryModel] {
        try await database.read { db in
            try StoryRecord.order(Column("updatedAt").desc, Column("id")).fetchAll(db)
                .map { StoryModel(record: $0) }
        }
    }

    /// Loads messages and their choices in one consistent database snapshot.
    func get(id: UUID) async throws -> StoryModel? {
        try await database.read { db in
            guard let record = try StoryRecord.filter(Column("id") == id.uuidString).fetchOne(db) else {
                return nil
            }
            var story = StoryModel(record: record)
            let actions = try StoryMessageActionRecord.filter(Column("storyId") == id.uuidString)
                .order(Column("position"), Column("id")).fetchAll(db)
            let actionsByMessage = Dictionary(grouping: actions, by: \.storyMessageId)
            story.storyMessages = try StoryMessageRecord.filter(Column("storyId") == id.uuidString)
                .order(Column("position"), Column("createdAt"), Column("id")).fetchAll(db)
                .map { record in
                    var message = StoryMessageModel(record: record)
                    message.actions = (actionsByMessage[record.id] ?? []).map { StoryMessageActionModel(record: $0) }
                    return message
                }
            return story
        }
    }

    /// Upserts the supplied story, messages, and actions atomically. Omitting a child does not delete it.
    /// Use the typed record repository for explicit child deletions.
    func save(_ story: StoryModel) async throws {
        try await database.write { db in
            var record = story.record
            record.updatedAt = .now
            try record.save(db)
            for message in story.storyMessages {
                guard message.storyId == story.id else {
                    throw AppDBError.invalidRelationship("Message belongs to another story.")
                }
                var record = message.record
                record.updatedAt = .now
                try record.save(db)
                for action in message.actions {
                    guard action.storyId == story.id, action.storyMessageId == message.id else {
                        throw AppDBError.invalidRelationship("Action belongs to another message or story.")
                    }
                    var record = action.record
                    record.updatedAt = .now
                    try record.save(db)
                }
            }
        }
    }

    @discardableResult
    func delete(id: UUID) async throws -> Bool {
        try await RecordRepository<StoryRecord>(database: database).delete(id: id)
    }
}
