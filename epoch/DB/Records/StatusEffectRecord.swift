import Foundation
import GRDB

nonisolated struct StatusEffectRecord: EpochRecord {
    static let databaseTableName = "status_effect"

    static let story = belongsTo(StoryRecord.self, using: ForeignKey(["storyId"], to: ["id"]))
    static let playerCharacter = belongsTo(PlayerCharacterRecord.self, using: ForeignKey(["playerCharacterId"], to: ["id"]))
    static let nonPlayerCharacter = belongsTo(NonPlayerCharacterRecord.self, using: ForeignKey(["nonPlayerCharacterId"], to: ["id"]))

    var id: UUID = UUID()
    var createdAt: Date = .now
    var updatedAt: Date = .now
    var storyId: UUID
    var playerCharacterId: UUID? = nil
    var nonPlayerCharacterId: UUID? = nil
    var name: String
    var description: String = ""
    var modifiers: [StatusEffectModifier] = []
    var customEffects: [String: String] = [:]
    var removalConditions: [String] = []
    var turnsRemaining: Int? = nil

    static func migrateTable(_ db: Database) throws {
        try db.create(table: databaseTableName) { t in
            t.column("id", .text).primaryKey().notNull()
            t.column("createdAt", .datetime).notNull().defaults(sql: "CURRENT_TIMESTAMP")
            t.column("updatedAt", .datetime).notNull().defaults(sql: "CURRENT_TIMESTAMP")
            t.column("storyId", .text).notNull().references(StoryRecord.databaseTableName, onDelete: .cascade)
            t.column("playerCharacterId", .text)
            t.column("nonPlayerCharacterId", .text)
            t.column("name", .text).notNull()
            t.column("description", .text).notNull().defaults(to: "")
            t.column("modifiers", .text).notNull()
                .check { Database.jsonIsValid($0) && Database.jsonType($0) == "array" }
                .defaults(to: "[]")
            t.column("customEffects", .text).notNull()
                .check { Database.jsonIsValid($0) && Database.jsonType($0) == "object" }
                .defaults(to: "{}")
            t.column("removalConditions", .text).notNull()
                .check { Database.jsonIsValid($0) && Database.jsonType($0) == "array" }
                .defaults(to: "[]")
            t.column("turnsRemaining", .integer).check { $0 == nil || $0 >= 0 }
            t.uniqueKey(["storyId", "id"])
            t.check(
                (Column("playerCharacterId") != nil && Column("nonPlayerCharacterId") == nil)
                || (Column("playerCharacterId") == nil && Column("nonPlayerCharacterId") != nil)
            )
            t.foreignKey(["playerCharacterId"], references: PlayerCharacterRecord.databaseTableName, columns: ["id"], onDelete: .cascade)
            t.foreignKey(["storyId", "playerCharacterId"], references: PlayerCharacterRecord.databaseTableName, columns: ["storyId", "id"])
            t.foreignKey(["nonPlayerCharacterId"], references: NonPlayerCharacterRecord.databaseTableName, columns: ["id"], onDelete: .cascade)
            t.foreignKey(["storyId", "nonPlayerCharacterId"], references: NonPlayerCharacterRecord.databaseTableName, columns: ["storyId", "id"])
        }
        try db.create(index: "status_effect_storyId", on: databaseTableName, columns: ["storyId"])
        try db.create(index: "status_effect_playerCharacterId", on: databaseTableName, columns: ["playerCharacterId"])
        try db.create(index: "status_effect_nonPlayerCharacterId", on: databaseTableName, columns: ["nonPlayerCharacterId"])
    }
}
