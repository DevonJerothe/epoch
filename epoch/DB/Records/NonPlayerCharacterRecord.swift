import Foundation
import GRDB

nonisolated struct NonPlayerCharacterRecord: EpochRecord {
    static let databaseTableName = "non_player_character"

    static let statusEffects = hasMany(StatusEffectRecord.self, using: ForeignKey(["nonPlayerCharacterId"], to: ["id"])).forKey("statusEffects")
    static let story = belongsTo(StoryRecord.self, using: ForeignKey(["storyId"], to: ["id"]))
    static let location = belongsTo(LocationRecord.self, using: ForeignKey(["locationId"], to: ["id"]))
    static let inventory = hasMany(PlayerInventoryRecord.self, using: ForeignKey(["nonPlayerCharacterId"], to: ["id"])).forKey("inventory")
    static let quests = hasMany(QuestRecord.self, using: ForeignKey(["giverId"], to: ["id"])).forKey("quests")

    var id: UUID = UUID()
    var createdAt: Date = .now
    var updatedAt: Date = .now
    var storyId: UUID
    var name: String
    var description: String = ""
    var role: String = ""
    var disposition: String = "neutral"
    var attributes: [String: Int] = [:]
    var isAlive: Bool = true
    var locationId: UUID? = nil
    var image: Data? = nil

    static func migrateTable(_ db: Database) throws {
        try db.create(table: databaseTableName) { t in
            t.column("id", .text).primaryKey().notNull()
            t.column("createdAt", .datetime).notNull()
                .defaults(sql: "CURRENT_TIMESTAMP")
            t.column("updatedAt", .datetime).notNull()
                .defaults(sql: "CURRENT_TIMESTAMP")
            t.column("storyId", .text).notNull().references(StoryRecord.databaseTableName, onDelete: .cascade)
            t.column("name", .text).notNull()
            t.column("description", .text).notNull()
                .defaults(to: "")
            t.column("role", .text).notNull()
                .defaults(to: "")
            t.column("disposition", .text).notNull()
                .defaults(to: "neutral")
            t.column("isAlive", .boolean).notNull()
                .check { [0, 1].contains($0) }
                .defaults(to: true)
            t.column("locationId", .text)
            t.column("image", .blob)
            t.uniqueKey(["storyId", "id"])
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
        }

        try db.create(index: "non_player_character_storyId", on: databaseTableName, columns: ["storyId"])
        try db.create(index: "non_player_character_locationId", on: databaseTableName, columns: ["locationId"])
    }

    static func migrateAttributes(_ db: Database) throws {
        try db.alter(table: databaseTableName) { t in
            t.add(column: "attributes", .text).notNull()
                .check { Database.jsonIsValid($0) && Database.jsonType($0) == "object" }
                .defaults(to: "{}")
        }
    }
}
