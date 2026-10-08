import Foundation
import GRDB

nonisolated struct StoryMessageRecord: EpochRecord {
    static let databaseTableName = "story_message"

    static let story = belongsTo(StoryRecord.self, using: ForeignKey(["storyId"], to: ["id"]))
    static let actions = hasMany(StoryMessageActionRecord.self, using: ForeignKey(["storyMessageId"], to: ["id"])).forKey("actions")

    var id: UUID = UUID()
    var createdAt: Date = .now
    var updatedAt: Date = .now
    var storyId: UUID
    var actor: MessageActor
    var status: MessageStatus = .done
    var text: String = ""
    var messageImage: Data? = nil
    var tokenCount: Int = 0
    var position: Int = 0

    static func migrateTable(_ db: Database) throws {
        try db.create(table: databaseTableName) { t in
            t.column("id", .text).primaryKey().notNull()
            t.column("createdAt", .datetime).notNull()
                .defaults(sql: "CURRENT_TIMESTAMP")
            t.column("updatedAt", .datetime).notNull()
                .defaults(sql: "CURRENT_TIMESTAMP")
            t.column("storyId", .text).notNull().references(StoryRecord.databaseTableName, onDelete: .cascade)
            t.column("actor", .integer).notNull()
                .check { [0, 1].contains($0) }
            t.column("status", .integer).notNull()
                .check { [0, 1, 2, 3].contains($0) }
                .defaults(to: 3)
            t.column("text", .text).notNull()
                .defaults(to: "")
            t.column("messageImage", .blob)
            t.column("tokenCount", .integer).notNull()
                .check { $0 >= 0 }
                .defaults(to: 0)
            t.column("position", .integer).notNull()
                .check { $0 >= 0 }
                .defaults(to: 0)
            t.uniqueKey(["storyId", "id"])
        }

        try db.create(index: "story_message_storyId", on: databaseTableName, columns: ["storyId"])
        try db.create(
            index: "story_message_order",
            on: databaseTableName,
            columns: ["storyId", "position", "createdAt", "id"]
        )
    }
}
