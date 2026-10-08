import GRDB

nonisolated enum DatabaseMigrations {
    static func migrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_story_world") { db in
            try StoryRecord.migrateTable(db)
            try LocationRecord.migrateTable(db)
            try PlayerCharacterRecord.migrateTable(db)
            try ItemRecord.migrateTable(db)
            try NonPlayerCharacterRecord.migrateTable(db)
            try StoryMessageRecord.migrateTable(db)
            try PlayerInventoryRecord.migrateInitialTable(db)
            try QuestRecord.migrateTable(db)
            try LoreItemRecord.migrateTable(db)
            try StoryMessageActionRecord.migrateTable(db)
        }
        migrator.registerMigration("v2_character_effects_and_npc_inventory") { db in
            try NonPlayerCharacterRecord.migrateAttributes(db)
            try PlayerInventoryRecord.migrateCharacterOwnership(db)
            try StatusEffectRecord.migrateTable(db)
        }
        return migrator
    }
}
