import Foundation
import GRDB

nonisolated struct PlayerInventoryRecord: EpochRecord {
    static let databaseTableName = "player_inventory"

    static let story = belongsTo(StoryRecord.self, using: ForeignKey(["storyId"], to: ["id"]))
    static let playerCharacter = belongsTo(PlayerCharacterRecord.self, using: ForeignKey(["playerCharacterId"], to: ["id"]))
    static let nonPlayerCharacter = belongsTo(NonPlayerCharacterRecord.self, using: ForeignKey(["nonPlayerCharacterId"], to: ["id"]))
    static let item = belongsTo(ItemRecord.self, using: ForeignKey(["itemId"], to: ["id"]))

    var id: UUID = UUID()
    var createdAt: Date = .now
    var updatedAt: Date = .now
    var storyId: UUID
    var playerCharacterId: UUID? = nil
    var nonPlayerCharacterId: UUID? = nil
    var itemId: UUID
    var quantity: Int = 1
    var equipmentSlot: String? = nil

    static func migrateTable(_ db: Database) throws {
        try db.create(table: databaseTableName) { t in
            t.column("id", .text).primaryKey().notNull()
            t.column("createdAt", .datetime).notNull()
                .defaults(sql: "CURRENT_TIMESTAMP")
            t.column("updatedAt", .datetime).notNull()
                .defaults(sql: "CURRENT_TIMESTAMP")
            t.column("storyId", .text).notNull().references(StoryRecord.databaseTableName, onDelete: .cascade)
            t.column("playerCharacterId", .text)
            t.column("nonPlayerCharacterId", .text)
            t.column("itemId", .text).notNull()
            t.column("quantity", .integer).notNull()
                .check { $0 > 0 }
                .defaults(to: 1)
            t.column("equipmentSlot", .text)
            t.uniqueKey(["storyId", "id"])
            t.foreignKey(
                ["playerCharacterId"],
                references: PlayerCharacterRecord.databaseTableName,
                columns: ["id"],
                onDelete: .cascade
            )
            t.foreignKey(
                ["storyId", "playerCharacterId"],
                references: PlayerCharacterRecord.databaseTableName,
                columns: ["storyId", "id"]
            )
            t.foreignKey(["itemId"], references: ItemRecord.databaseTableName, columns: ["id"], onDelete: .cascade)
            t.foreignKey(["storyId", "itemId"], references: ItemRecord.databaseTableName, columns: ["storyId", "id"])
            t.foreignKey(["nonPlayerCharacterId"], references: NonPlayerCharacterRecord.databaseTableName, columns: ["id"], onDelete: .cascade)
            t.foreignKey(["storyId", "nonPlayerCharacterId"], references: NonPlayerCharacterRecord.databaseTableName, columns: ["storyId", "id"])
            t.check(
                (Column("playerCharacterId") != nil && Column("nonPlayerCharacterId") == nil)
                || (Column("playerCharacterId") == nil && Column("nonPlayerCharacterId") != nil)
            )
            t.uniqueKey(["playerCharacterId", "itemId"])
            t.uniqueKey(["nonPlayerCharacterId", "itemId"])
            t.check(sql: "equipmentSlot IS NULL OR (length(trim(equipmentSlot)) > 0 AND quantity = 1)")
        }

        try db.create(index: "player_inventory_storyId", on: databaseTableName, columns: ["storyId"])
        try db.create(
            index: "player_inventory_playerCharacterId",
            on: databaseTableName,
            columns: ["playerCharacterId"]
        )
        try db.create(index: "player_inventory_nonPlayerCharacterId", on: databaseTableName, columns: ["nonPlayerCharacterId"])
        try db.create(index: "player_inventory_itemId", on: databaseTableName, columns: ["itemId"])
        try db.create(
            index: "player_inventory_equipment_slot",
            on: databaseTableName,
            columns: ["playerCharacterId", "equipmentSlot"],
            unique: true,
            condition: Column("equipmentSlot") != nil
        )
        try db.create(
            index: "player_inventory_npc_equipment_slot",
            on: databaseTableName,
            columns: ["nonPlayerCharacterId", "equipmentSlot"],
            unique: true,
            condition: Column("equipmentSlot") != nil
        )
    }
}
