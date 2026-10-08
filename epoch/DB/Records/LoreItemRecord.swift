import Foundation
import GRDB

nonisolated struct LoreItemRecord: EpochRecord {
    static let databaseTableName = "lore_item"

    static let story = belongsTo(StoryRecord.self, using: ForeignKey(["storyId"], to: ["id"]))
    static let location = belongsTo(LocationRecord.self, using: ForeignKey(["locationId"], to: ["id"]))
    static let nonPlayerCharacter = belongsTo(NonPlayerCharacterRecord.self, using: ForeignKey(["nonPlayerCharacterId"], to: ["id"]))
    static let item = belongsTo(ItemRecord.self, using: ForeignKey(["itemId"], to: ["id"]))

    var id: UUID = UUID()
    var createdAt: Date = .now
    var updatedAt: Date = .now
    var storyId: UUID
    var title: String
    var text: String = ""
    var category: String = "general"
    var keywords: [String] = []
    var isDiscovered: Bool = false
    var locationId: UUID? = nil
    var nonPlayerCharacterId: UUID? = nil
    var itemId: UUID? = nil

    static func migrateTable(_ db: Database) throws {
        try db.create(table: databaseTableName) { t in
            t.column("id", .text).primaryKey().notNull()
            t.column("createdAt", .datetime).notNull()
                .defaults(sql: "CURRENT_TIMESTAMP")
            t.column("updatedAt", .datetime).notNull()
                .defaults(sql: "CURRENT_TIMESTAMP")
            t.column("storyId", .text).notNull().references(StoryRecord.databaseTableName, onDelete: .cascade)
            t.column("title", .text).notNull()
            t.column("text", .text).notNull()
                .defaults(to: "")
            t.column("category", .text).notNull()
                .defaults(to: "general")
            t.column("keywords", .text).notNull()
                .check { Database.jsonIsValid($0) && Database.jsonType($0) == "array" }
                .defaults(to: "[]")
            t.column("isDiscovered", .boolean).notNull()
                .check { [0, 1].contains($0) }
                .defaults(to: false)
            t.column("locationId", .text)
            t.column("nonPlayerCharacterId", .text)
            t.column("itemId", .text)
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
        }

        try db.create(index: "lore_item_storyId", on: databaseTableName, columns: ["storyId"])
        try db.create(index: "lore_item_locationId", on: databaseTableName, columns: ["locationId"])
        try db.create(index: "lore_item_nonPlayerCharacterId", on: databaseTableName, columns: ["nonPlayerCharacterId"])
        try db.create(index: "lore_item_itemId", on: databaseTableName, columns: ["itemId"])
    }
}
