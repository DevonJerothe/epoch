import Foundation
import GRDB

nonisolated struct StoryMessageActionRecord: EpochRecord {
    static let databaseTableName = "story_message_action"

    static let story = belongsTo(StoryRecord.self, using: ForeignKey(["storyId"], to: ["id"]))
    static let storyMessage = belongsTo(StoryMessageRecord.self, using: ForeignKey(["storyMessageId"], to: ["id"]))
    static let location = belongsTo(LocationRecord.self, using: ForeignKey(["locationId"], to: ["id"]))
    static let nonPlayerCharacter = belongsTo(NonPlayerCharacterRecord.self, using: ForeignKey(["nonPlayerCharacterId"], to: ["id"]))
    static let item = belongsTo(ItemRecord.self, using: ForeignKey(["itemId"], to: ["id"]))
    static let quest = belongsTo(QuestRecord.self, using: ForeignKey(["questId"], to: ["id"]))

    var id: UUID = UUID()
    var createdAt: Date = .now
    var updatedAt: Date = .now
    var storyId: UUID
    var storyMessageId: UUID
    var title: String
    var text: String = ""
    var kind: StoryMessageActionKind = .narrative
    var status: StoryMessageActionStatus = .available
    var position: Int = 0
    var resolvedAt: Date? = nil
    var locationId: UUID? = nil
    var nonPlayerCharacterId: UUID? = nil
    var itemId: UUID? = nil
    var questId: UUID? = nil

    static func migrateTable(_ db: Database) throws {
        try db.create(table: databaseTableName) { t in
            t.column("id", .text).primaryKey().notNull()
            t.column("createdAt", .datetime).notNull()
                .defaults(sql: "CURRENT_TIMESTAMP")
            t.column("updatedAt", .datetime).notNull()
                .defaults(sql: "CURRENT_TIMESTAMP")
            t.column("storyId", .text).notNull().references(StoryRecord.databaseTableName, onDelete: .cascade)
            t.column("storyMessageId", .text).notNull()
            t.column("title", .text).notNull()
            t.column("text", .text).notNull()
                .defaults(to: "")
            t.column("kind", .text).notNull()
                .check { ["narrative", "travel", "dialogue", "combat", "inventory", "quest"].contains($0) }
                .defaults(to: "narrative")
            t.column("status", .text).notNull()
                .check { ["available", "selected", "resolved", "disabled"].contains($0) }
                .defaults(to: "available")
            t.column("position", .integer).notNull()
                .check { $0 >= 0 }
                .defaults(to: 0)
            t.column("resolvedAt", .datetime)
            t.column("locationId", .text)
            t.column("nonPlayerCharacterId", .text)
            t.column("itemId", .text)
            t.column("questId", .text)
            t.uniqueKey(["storyId", "id"])
            t.foreignKey(
                ["storyMessageId"],
                references: StoryMessageRecord.databaseTableName,
                columns: ["id"],
                onDelete: .cascade
            )
            t.foreignKey(
                ["storyId", "storyMessageId"],
                references: StoryMessageRecord.databaseTableName,
                columns: ["storyId", "id"]
            )
            t.foreignKey(
                ["locationId"],
                references: LocationRecord.databaseTableName,
                columns: ["id"],
                onDelete: .setNull
            )
            t.foreignKey(
                ["storyId", "locationId"],
                references: LocationRecord.databaseTableName,
                columns: ["storyId", "id"]
            )
            t.foreignKey(
                ["nonPlayerCharacterId"],
                references: NonPlayerCharacterRecord.databaseTableName,
                columns: ["id"],
                onDelete: .setNull
            )
            t.foreignKey(
                ["storyId", "nonPlayerCharacterId"],
                references: NonPlayerCharacterRecord.databaseTableName,
                columns: ["storyId", "id"]
            )
            t.foreignKey(["itemId"], references: ItemRecord.databaseTableName, columns: ["id"], onDelete: .setNull)
            t.foreignKey(["storyId", "itemId"], references: ItemRecord.databaseTableName, columns: ["storyId", "id"])
            t.foreignKey(["questId"], references: QuestRecord.databaseTableName, columns: ["id"], onDelete: .setNull)
            t.foreignKey(["storyId", "questId"], references: QuestRecord.databaseTableName, columns: ["storyId", "id"])
            t.uniqueKey(["storyMessageId", "position"])
        }

        try db.create(index: "story_message_action_storyId", on: databaseTableName, columns: ["storyId"])
        try db.create(index: "story_message_action_storyMessageId", on: databaseTableName, columns: ["storyMessageId"])
        try db.create(index: "story_message_action_locationId", on: databaseTableName, columns: ["locationId"])
        try db.create(
            index: "story_message_action_nonPlayerCharacterId",
            on: databaseTableName,
            columns: ["nonPlayerCharacterId"]
        )
        try db.create(index: "story_message_action_itemId", on: databaseTableName, columns: ["itemId"])
        try db.create(index: "story_message_action_questId", on: databaseTableName, columns: ["questId"])
        try db.create(
            index: "story_message_action_order",
            on: databaseTableName,
            columns: ["storyMessageId", "position"]
        )
    }
}
