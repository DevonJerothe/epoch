import Foundation
import GRDB

nonisolated struct QuestRecord: EpochRecord {
    static let databaseTableName = "quest"

    static let story = belongsTo(StoryRecord.self, using: ForeignKey(["storyId"], to: ["id"]))
    static let giver = belongsTo(NonPlayerCharacterRecord.self, using: ForeignKey(["giverId"], to: ["id"]))
    static let location = belongsTo(LocationRecord.self, using: ForeignKey(["locationId"], to: ["id"]))
    static let playerCharacter = belongsTo(PlayerCharacterRecord.self, using: ForeignKey(["playerCharacterId"], to: ["id"]))

    var id: UUID = UUID()
    var createdAt: Date = .now
    var updatedAt: Date = .now
    var storyId: UUID
    var title: String
    var description: String = ""
    var status: QuestStatus = .available
    var objectives: [QuestObjective] = []
    var rewardExperience: Int = 0
    var rewardCurrency: Int = 0
    var giverId: UUID? = nil
    var locationId: UUID? = nil
    var playerCharacterId: UUID? = nil
    var completedAt: Date? = nil

    static func migrateTable(_ db: Database) throws {
        try db.create(table: databaseTableName) { t in
            t.column("id", .text).primaryKey().notNull()
            t.column("createdAt", .datetime).notNull()
                .defaults(sql: "CURRENT_TIMESTAMP")
            t.column("updatedAt", .datetime).notNull()
                .defaults(sql: "CURRENT_TIMESTAMP")
            t.column("storyId", .text).notNull().references(StoryRecord.databaseTableName, onDelete: .cascade)
            t.column("title", .text).notNull()
            t.column("description", .text).notNull()
                .defaults(to: "")
            t.column("status", .text).notNull()
                .check { ["available", "active", "completed", "failed", "abandoned"].contains($0) }
                .defaults(to: "available")
            t.column("objectives", .text).notNull()
                .check { Database.jsonIsValid($0) && Database.jsonType($0) == "array" }
                .defaults(to: "[]")
            t.column("rewardExperience", .integer).notNull()
                .check { $0 >= 0 }
                .defaults(to: 0)
            t.column("rewardCurrency", .integer).notNull()
                .check { $0 >= 0 }
                .defaults(to: 0)
            t.column("giverId", .text)
            t.column("locationId", .text)
            t.column("playerCharacterId", .text)
            t.column("completedAt", .datetime)
            t.uniqueKey(["storyId", "id"])
            t.foreignKey(
                ["giverId"],
                references: NonPlayerCharacterRecord.databaseTableName,
                columns: ["id"],
                onDelete: .setNull
            )
            t.foreignKey(
                ["storyId", "giverId"],
                references: NonPlayerCharacterRecord.databaseTableName,
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
                ["playerCharacterId"],
                references: PlayerCharacterRecord.databaseTableName,
                columns: ["id"],
                onDelete: .setNull
            )
            t.foreignKey(
                ["storyId", "playerCharacterId"],
                references: PlayerCharacterRecord.databaseTableName,
                columns: ["storyId", "id"]
            )
        }

        try db.create(index: "quest_storyId", on: databaseTableName, columns: ["storyId"])
        try db.create(index: "quest_giverId", on: databaseTableName, columns: ["giverId"])
        try db.create(index: "quest_locationId", on: databaseTableName, columns: ["locationId"])
        try db.create(index: "quest_playerCharacterId", on: databaseTableName, columns: ["playerCharacterId"])
        try db.create(index: "quest_story_status", on: databaseTableName, columns: ["storyId", "status"])
    }
}
