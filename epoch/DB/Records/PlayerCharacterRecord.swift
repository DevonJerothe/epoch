import Foundation
import GRDB

nonisolated struct PlayerCharacterRecord: EpochRecord {
    static let databaseTableName = "player_character"

    static let statusEffects = hasMany(StatusEffectRecord.self, using: ForeignKey(["playerCharacterId"], to: ["id"])).forKey("statusEffects")
    static let story = belongsTo(StoryRecord.self, using: ForeignKey(["storyId"], to: ["id"]))
    static let location = belongsTo(LocationRecord.self, using: ForeignKey(["locationId"], to: ["id"]))
    static let inventory = hasMany(PlayerInventoryRecord.self, using: ForeignKey(["playerCharacterId"], to: ["id"])).forKey("inventory")
    static let quests = hasMany(QuestRecord.self, using: ForeignKey(["playerCharacterId"], to: ["id"])).forKey("quests")

    var id: UUID = UUID()
    var createdAt: Date = .now
    var updatedAt: Date = .now
    var storyId: UUID
    var name: String
    var description: String = ""
    var characterClass: String = ""
    var level: Int = 1
    var experience: Int = 0
    var health: Int = 100
    var maxHealth: Int = 100
    var currency: Int = 0
    var attributes: [String: Int] = [:]
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
            t.column("characterClass", .text).notNull()
                .defaults(to: "")
            t.column("level", .integer).notNull()
                .check { $0 >= 1 }
                .defaults(to: 1)
            t.column("experience", .integer).notNull()
                .check { $0 >= 0 }
                .defaults(to: 0)
            t.column("health", .integer).notNull()
                .check { $0 >= 0 && $0 <= Column("maxHealth") }
                .defaults(to: 100)
            t.column("maxHealth", .integer).notNull()
                .check { $0 > 0 }
                .defaults(to: 100)
            t.column("currency", .integer).notNull()
                .check { $0 >= 0 }
                .defaults(to: 0)
            t.column("attributes", .text).notNull()
                .check { Database.jsonIsValid($0) && Database.jsonType($0) == "object" }
                .defaults(to: "{}")
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

        try db.create(index: "player_character_storyId", on: databaseTableName, columns: ["storyId"])
        try db.create(index: "player_character_locationId", on: databaseTableName, columns: ["locationId"])
    }
}
