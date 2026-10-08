import Foundation
import GRDB

nonisolated struct LocationRecord: EpochRecord {
    static let databaseTableName = "location"

    static let story = belongsTo(StoryRecord.self, using: ForeignKey(["storyId"], to: ["id"]))
    static let parentLocation = belongsTo(LocationRecord.self, using: ForeignKey(["parentLocationId"], to: ["id"]))
    static let children = hasMany(LocationRecord.self, using: ForeignKey(["parentLocationId"], to: ["id"])).forKey("children")
    static let playerCharacters = hasMany(PlayerCharacterRecord.self, using: ForeignKey(["locationId"], to: ["id"])).forKey("playerCharacters")
    static let nonPlayerCharacters = hasMany(NonPlayerCharacterRecord.self, using: ForeignKey(["locationId"], to: ["id"])).forKey("nonPlayerCharacters")
    static let quests = hasMany(QuestRecord.self, using: ForeignKey(["locationId"], to: ["id"])).forKey("quests")

    var id: UUID = UUID()
    var createdAt: Date = .now
    var updatedAt: Date = .now
    var storyId: UUID
    var name: String
    var description: String = ""
    var parentLocationId: UUID? = nil
    var isDiscovered: Bool = false
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
            t.column("parentLocationId", .text)
            t.column("isDiscovered", .boolean).notNull()
                .check { [0, 1].contains($0) }
                .defaults(to: false)
            t.column("image", .blob)
            t.uniqueKey(["storyId", "id"])
            t.foreignKey(
                ["parentLocationId"],
                references: LocationRecord.databaseTableName,
                columns: ["id"],
                onDelete: .setNull
            )
            t.foreignKey(
                ["storyId", "parentLocationId"],
                references: LocationRecord.databaseTableName,
                columns: ["storyId", "id"]
            )
            t.check(Column("parentLocationId") == nil || Column("parentLocationId") != Column("id"))
        }

        try db.create(index: "location_storyId", on: databaseTableName, columns: ["storyId"])
        try db.create(index: "location_parentLocationId", on: databaseTableName, columns: ["parentLocationId"])
    }
}
