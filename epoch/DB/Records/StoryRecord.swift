import Foundation
import GRDB

nonisolated struct StoryRecord: EpochRecord {
    static let databaseTableName = "story"

    static let statusEffects = hasMany(StatusEffectRecord.self, using: ForeignKey(["storyId"], to: ["id"])).forKey("statusEffects")
    static let storyMessages = hasMany(StoryMessageRecord.self, using: ForeignKey(["storyId"], to: ["id"])).forKey("storyMessages")
    static let playerCharacters = hasMany(PlayerCharacterRecord.self, using: ForeignKey(["storyId"], to: ["id"])).forKey("playerCharacters")
    static let items = hasMany(ItemRecord.self, using: ForeignKey(["storyId"], to: ["id"])).forKey("items")
    static let nonPlayerCharacters = hasMany(NonPlayerCharacterRecord.self, using: ForeignKey(["storyId"], to: ["id"])).forKey("nonPlayerCharacters")
    static let locations = hasMany(LocationRecord.self, using: ForeignKey(["storyId"], to: ["id"])).forKey("locations")
    static let quests = hasMany(QuestRecord.self, using: ForeignKey(["storyId"], to: ["id"])).forKey("quests")
    static let loreItems = hasMany(LoreItemRecord.self, using: ForeignKey(["storyId"], to: ["id"])).forKey("loreItems")

    var id: UUID = UUID()
    var createdAt: Date = .now
    var updatedAt: Date = .now
    var title: String
    var description: String = ""
    var tags: [String] = []
    var image: Data? = nil

    static func migrateTable(_ db: Database) throws {
        try db.create(table: databaseTableName) { t in
            t.column("id", .text).primaryKey().notNull()
            t.column("createdAt", .datetime).notNull()
                .defaults(sql: "CURRENT_TIMESTAMP")
            t.column("updatedAt", .datetime).notNull()
                .defaults(sql: "CURRENT_TIMESTAMP")
            t.column("title", .text).notNull()
            t.column("description", .text).notNull()
                .defaults(to: "")
            t.column("tags", .text).notNull()
                .check { Database.jsonIsValid($0) && Database.jsonType($0) == "array" }
                .defaults(to: "[]")
            t.column("image", .blob)
        }
    }
}
