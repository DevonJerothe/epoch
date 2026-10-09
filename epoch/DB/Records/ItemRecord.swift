import Foundation
import GRDB

nonisolated struct ItemRecord: EpochRecord {
    static let databaseTableName = "item"

    static let story = belongsTo(StoryRecord.self, using: ForeignKey(["storyId"], to: ["id"]))
    static let inventory = hasMany(PlayerInventoryRecord.self, using: ForeignKey(["itemId"], to: ["id"])).forKey("inventory")

    var id: UUID = UUID()
    var createdAt: Date = .now
    var updatedAt: Date = .now
    var storyId: UUID
    var name: String
    var description: String = ""
    var category: String = "miscellaneous"
    var rarity: String = "common"
    var value: Int = 0
    var weight: Double = 0
    var isConsumable: Bool = false
    var effects: [String: Int] = [:]
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
            t.column("category", .text).notNull()
                .defaults(to: "miscellaneous")
            t.column("rarity", .text).notNull()
                .defaults(to: "common")
            t.column("value", .integer).notNull()
                .check { $0 >= 0 }
                .defaults(to: 0)
            t.column("weight", .double).notNull()
                .check { $0 >= 0 }
                .defaults(to: 0)
            t.column("isConsumable", .boolean).notNull()
                .check { [0, 1].contains($0) }
                .defaults(to: false)
            t.column("effects", .text).notNull()
                .check { Database.jsonIsValid($0) && Database.jsonType($0) == "object" }
                .defaults(to: "{}")
            t.column("image", .blob)
            t.uniqueKey(["storyId", "id"])
        }

        try db.create(index: "item_storyId", on: databaseTableName, columns: ["storyId"])
    }
}
