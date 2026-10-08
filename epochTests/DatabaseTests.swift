import Foundation
import GRDB
import Testing
@testable import epoch

@MainActor
struct DatabaseTests {
    @MainActor
    private struct World {
        let story = StoryModel(title: "The Last Epoch", tags: ["fantasy", "探索"], image: Data([1, 2]))
        var location: LocationModel
        var player: PlayerCharacterModel
        var item: ItemModel
        var npc: NonPlayerCharacterModel
        var quest: QuestModel
        var lore: LoreItemModel
        var inventory: PlayerInventoryModel
        var message: StoryMessageModel
        var action: StoryMessageActionModel
        var statusEffect: StatusEffectModel

        init() {
            location = LocationModel(storyId: story.id, name: "Old forest")
            player = PlayerCharacterModel(storyId: story.id, name: "Ari", attributes: ["strength": 12], locationId: location.id)
            item = ItemModel(storyId: story.id, name: "Lantern", effects: ["light": 2])
            npc = NonPlayerCharacterModel(storyId: story.id, name: "Keeper", attributes: ["stealth": 5], locationId: location.id)
            quest = QuestModel(storyId: story.id, title: "Find the path", objectives: [QuestObjective(description: "Light the lantern")], giverId: npc.id, locationId: location.id, playerCharacterId: player.id)
            lore = LoreItemModel(storyId: story.id, title: "The forest", keywords: ["forest"], locationId: location.id, nonPlayerCharacterId: npc.id, itemId: item.id)
            inventory = PlayerInventoryModel(storyId: story.id, playerCharacterId: player.id, itemId: item.id, equipmentSlot: "hand")
            message = StoryMessageModel(storyId: story.id, actor: .bot, text: "A path appears.", messageImage: Data([3, 4]), tokenCount: 4)
            statusEffect = StatusEffectModel(storyId: story.id, playerCharacterId: player.id, name: "Soaked", modifiers: [StatusEffectModifier(target: "attribute.stealth", operation: .add, value: -1)], removalConditions: ["drying_off"], turnsRemaining: 3)
            action = StoryMessageActionModel(storyId: story.id, storyMessageId: message.id, title: "Follow the path", kind: .travel, locationId: location.id, nonPlayerCharacterId: npc.id, itemId: item.id, questId: quest.id)
        }

        func save(in database: DBManager) throws {
            try database.write { db in
                try story.record.insert(db)
                try location.record.insert(db)
                try player.record.insert(db)
                try item.record.insert(db)
                try npc.record.insert(db)
                try quest.record.insert(db)
                try lore.record.insert(db)
                try inventory.record.insert(db)
                try message.record.insert(db)
                try action.record.insert(db)
                try statusEffect.record.insert(db)
            }
        }
    }

    @Test func migratesAndRoundTripsEveryTable() throws {
        let database = try DBManager(path: ":memory:")
        let world = World()
        try world.save(in: database)
        try database.read { (db: Database) throws -> Void in
            #expect(try Bool.fetchOne(db, sql: "PRAGMA foreign_keys") == true)
            #expect(try Row.fetchAll(db, sql: "PRAGMA foreign_key_check").isEmpty)
            let story = try #require(try StoryRecord.fetchOne(db))
            #expect(StoryModel(record: story).tags == world.story.tags)
            #expect(story.image == world.story.image)
            #expect(try PlayerCharacterRecord.fetchOne(db)?.attributes == ["strength": 12])
            #expect(try ItemRecord.fetchOne(db)?.effects == ["light": 2])
            #expect(try PlayerInventoryRecord.fetchOne(db)?.equipmentSlot == "hand")
            #expect(try LocationRecord.fetchOne(db)?.id == world.location.id)
            #expect(try NonPlayerCharacterRecord.fetchOne(db)?.locationId == world.location.id)
            #expect(try QuestRecord.fetchOne(db)?.objectives == world.quest.objectives)
            #expect(try LoreItemRecord.fetchOne(db)?.keywords == ["forest"])
            #expect(try StoryMessageRecord.fetchOne(db)?.messageImage == world.message.messageImage)
            #expect(try StoryMessageActionRecord.fetchOne(db)?.kind == .travel)
            #expect(try String.fetchOne(db, sql: "SELECT typeof(id) FROM story") == "text")
            #expect(try String.fetchOne(db, sql: "SELECT typeof(actor) FROM story_message") == "integer")
            // The GRDB association also handles the same UUID foreign key representation.
            let players = try story.request(for: StoryRecord.playerCharacters).fetchAll(db)
            #expect(players.map(\.id) == [world.player.id])
        }
        let repository = RecordRepository<PlayerCharacterRecord>(database: database)
        let player = try #require(try repository.get(id: world.player.id))
        #expect(PlayerCharacterModel(record: player).id == world.player.id)
        #expect(try repository.getAll().count == 1)
        let story = try #require(try StoryRepository(database: database).get(id: world.story.id))
        #expect(story.storyMessages.first?.actions.first?.id == world.action.id)
    }

    @Test func rejectsMissingParentsAndCrossStoryReferences() throws {
        let database = try DBManager(path: ":memory:")
        let world = World()
        try world.save(in: database)
        let otherStory = StoryModel(title: "Another world")
        try database.write { db in try otherStory.record.insert(db) }
        #expect(throws: DatabaseError.self) {
            try database.write { db in
                try ItemModel(storyId: UUID(), name: "Orphan").record.insert(db)
            }
        }
        #expect(throws: DatabaseError.self) {
            try database.write { db in
                try PlayerCharacterModel(storyId: otherStory.id, name: "Traveler", locationId: world.location.id).record.insert(db)
            }
        }
        #expect(throws: DatabaseError.self) {
            try database.write { db in
                try PlayerInventoryModel(storyId: otherStory.id, playerCharacterId: world.player.id, itemId: world.item.id).record.insert(db)
            }
        }
        #expect(throws: DatabaseError.self) {
            try database.write { db in
                try StoryMessageActionModel(storyId: otherStory.id, storyMessageId: world.message.id, title: "Invalid").record.insert(db)
            }
        }
        #expect(throws: DatabaseError.self) {
            try database.write { db in
                try db.execute(sql: "UPDATE item SET storyId = ? WHERE id = ?", arguments: [otherStory.id.uuidString, world.item.id.uuidString])
            }
        }
    }

    @Test func validatesInventoryAndGameValues() throws {
        let database = try DBManager(path: ":memory:")
        let world = World()
        try world.save(in: database)
        #expect(throws: DatabaseError.self) {
            try database.write { db in
                try PlayerInventoryModel(storyId: world.story.id, playerCharacterId: world.player.id, itemId: world.item.id).record.insert(db)
            }
        }
        for sql in [
            "UPDATE player_inventory SET quantity = 0",
            "UPDATE player_inventory SET quantity = 2",
            "UPDATE player_character SET health = maxHealth + 1",
            "UPDATE player_character SET level = 0",
            "UPDATE story_message SET tokenCount = -1",
            "UPDATE quest SET status = 'unknown'",
            "UPDATE item SET effects = '[]'"
        ] {
            #expect(throws: DatabaseError.self) { try database.write { db in try db.execute(sql: sql) } }
        }
        let secondItem = ItemModel(storyId: world.story.id, name: "Sword")
        try database.write { db in try secondItem.record.insert(db) }
        #expect(throws: DatabaseError.self) {
            try database.write { db in
                try PlayerInventoryModel(storyId: world.story.id, playerCharacterId: world.player.id, itemId: secondItem.id, equipmentSlot: "hand").record.insert(db)
            }
        }
        #expect(throws: DatabaseError.self) {
            try database.write { db in
                try StoryMessageActionModel(storyId: world.story.id, storyMessageId: world.message.id, title: "Duplicate position").record.insert(db)
            }
        }
    }

    @Test func deletingOptionalTargetsClearsReferencesAndPreservesHistory() throws {
        let database = try DBManager(path: ":memory:")
        let world = World()
        try world.save(in: database)
        #expect(try RecordRepository<LocationRecord>(database: database).delete(id: world.location.id))
        #expect(try RecordRepository<NonPlayerCharacterRecord>(database: database).delete(id: world.npc.id))
        #expect(try RecordRepository<ItemRecord>(database: database).delete(id: world.item.id))
        try database.read { (db: Database) throws -> Void in
            #expect(try PlayerCharacterRecord.fetchOne(db)?.locationId == nil)
            let quest = try #require(try QuestRecord.fetchOne(db))
            #expect(quest.locationId == nil)
            #expect(quest.giverId == nil)
            let action = try #require(try StoryMessageActionRecord.fetchOne(db))
            #expect(action.locationId == nil)
            #expect(action.nonPlayerCharacterId == nil)
            #expect(action.itemId == nil)
            #expect(try PlayerInventoryRecord.fetchCount(db) == 0)
            #expect(try StoryMessageRecord.fetchCount(db) == 1)
            #expect(try Row.fetchAll(db, sql: "PRAGMA foreign_key_check").isEmpty)
        }
    }

    @Test func deletingStoryCascadesOnlyItsWorld() throws {
        let database = try DBManager(path: ":memory:")
        let world = World()
        try world.save(in: database)
        let otherWorld = World()
        try otherWorld.save(in: database)
        #expect(try StoryRepository(database: database).delete(id: world.story.id))
        try database.read { (db: Database) throws -> Void in
            for table in ["story", "story_message", "player_character", "player_inventory", "item", "non_player_character", "location", "quest", "lore_item", "story_message_action", "status_effect"] {
                #expect(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table)") == 1)
            }
            #expect(try Row.fetchAll(db, sql: "PRAGMA foreign_key_check").isEmpty)
        }
        #expect(try StoryRepository(database: database).get(id: otherWorld.story.id) != nil)
    }

    @Test func aggregateSaveRollsBackAndOrdersMessages() throws {
        let database = try DBManager(path: ":memory:")
        let repository = StoryRepository(database: database)
        var story = StoryModel(title: "Ordered")
        let second = StoryMessageModel(storyId: story.id, actor: .user, text: "Second", position: 1)
        var first = StoryMessageModel(storyId: story.id, actor: .bot, text: "First", position: 0)
        first.actions = [StoryMessageActionModel(storyId: story.id, storyMessageId: first.id, title: "Continue")]
        story.storyMessages = [second, first]
        try repository.save(story)
        let loaded = try #require(try repository.get(id: story.id))
        #expect(loaded.storyMessages.map(\.text) == ["First", "Second"])
        #expect(loaded.storyMessages.first?.actions.count == 1)
        story.title = "Must roll back"
        story.storyMessages.append(StoryMessageModel(storyId: UUID(), actor: .bot))
        #expect(throws: AppDBError.self) { try repository.save(story) }
        #expect(try repository.get(id: story.id)?.title == "Ordered")
        #expect(try RecordRepository<StoryMessageRecord>(database: database).delete(id: first.id))
        #expect(try RecordRepository<StoryMessageActionRecord>(database: database).getAll().isEmpty)
    }

    @Test func reopeningFilePreservesDataAndDoesNotRepeatMigration() throws {
        let directory = URL.temporaryDirectory.appending(path: "epoch-db-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appending(path: "epoch.sqlite").path
        let story = StoryModel(title: "Persistent")
        do {
            let database = try DBManager(path: path)
            try StoryRepository(database: database).save(story)
            #expect(try database.read { try String.fetchOne($0, sql: "PRAGMA journal_mode") } == "wal")
        }
        let reopened = try DBManager(path: path)
        #expect(try StoryRepository(database: reopened).get(id: story.id)?.title == "Persistent")
        #expect(try reopened.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM grdb_migrations") } == 2)
    }

    @Test func statusEffectsSupportBothCharactersAndCustomModifiers() throws {
        let database = try DBManager(path: ":memory:")
        let world = World()
        try world.save(in: database)
        let goldenFingers = StatusEffectModel(
            storyId: world.story.id,
            nonPlayerCharacterId: world.npc.id,
            name: "Golden Fingers",
            modifiers: [StatusEffectModifier(target: "loot.container.gold", operation: .multiply, value: 1.1)],
            customEffects: ["onLoot": "sparkle"]
        )
        try RecordRepository<StatusEffectRecord>(database: database).save(goldenFingers.record)
        try database.read { (db: Database) throws -> Void in
            let playerEffects = try world.player.record.request(for: PlayerCharacterRecord.statusEffects).fetchAll(db)
            let npcEffects = try world.npc.record.request(for: NonPlayerCharacterRecord.statusEffects).fetchAll(db)
            let soaked = try #require(playerEffects.first)
            #expect(soaked.modifiers == world.statusEffect.modifiers)
            #expect(soaked.removalConditions == ["drying_off"])
            #expect(soaked.turnsRemaining == 3)
            let golden = try #require(npcEffects.first)
            #expect(golden.modifiers == goldenFingers.modifiers)
            #expect(golden.customEffects == ["onLoot": "sparkle"])
            #expect(StatusEffectModel(record: golden).isActive)
            #expect(try NonPlayerCharacterRecord.fetchOne(db)?.attributes == ["stealth": 5])
        }
        var expired = world.statusEffect
        expired.turnsRemaining = 0
        #expect(!expired.isActive)
        try RecordRepository<StatusEffectRecord>(database: database).save(expired.record)
        #expect(try RecordRepository<StatusEffectRecord>(database: database).get(id: expired.id)?.turnsRemaining == 0)
        let otherStory = StoryModel(title: "Other")
        try database.write { db in try otherStory.record.insert(db) }
        var invalid = goldenFingers
        invalid.id = UUID()
        invalid.storyId = otherStory.id
        #expect(throws: DatabaseError.self) { try RecordRepository<StatusEffectRecord>(database: database).save(invalid.record) }
        invalid.storyId = world.story.id
        invalid.playerCharacterId = world.player.id
        #expect(throws: DatabaseError.self) { try RecordRepository<StatusEffectRecord>(database: database).save(invalid.record) }
        invalid.playerCharacterId = nil
        invalid.nonPlayerCharacterId = nil
        #expect(throws: DatabaseError.self) { try RecordRepository<StatusEffectRecord>(database: database).save(invalid.record) }
        invalid.playerCharacterId = world.player.id
        invalid.turnsRemaining = -1
        #expect(throws: DatabaseError.self) { try RecordRepository<StatusEffectRecord>(database: database).save(invalid.record) }
        try RecordRepository<NonPlayerCharacterRecord>(database: database).delete(id: world.npc.id)
        #expect(try RecordRepository<StatusEffectRecord>(database: database).get(id: goldenFingers.id) == nil)
        #expect(try RecordRepository<StatusEffectRecord>(database: database).get(id: world.statusEffect.id) != nil)
        try RecordRepository<PlayerCharacterRecord>(database: database).delete(id: world.player.id)
        #expect(try RecordRepository<StatusEffectRecord>(database: database).getAll().isEmpty)
    }

    @Test func npcInventoryEnforcesOwnershipStackAndEquipmentRules() throws {
        let database = try DBManager(path: ":memory:")
        let world = World()
        try world.save(in: database)
        let inventory = PlayerInventoryModel(storyId: world.story.id, nonPlayerCharacterId: world.npc.id, itemId: world.item.id, equipmentSlot: "hand")
        let repository = RecordRepository<PlayerInventoryRecord>(database: database)
        try repository.save(inventory.record)
        try database.read { (db: Database) throws -> Void in
            let ownedItems = try world.npc.record.request(for: NonPlayerCharacterRecord.inventory).fetchAll(db)
            let loaded = PlayerInventoryModel(record: try #require(ownedItems.first))
            #expect(loaded.nonPlayerCharacterId == world.npc.id)
            #expect(loaded.playerCharacterId == nil)
        }
        var invalid = inventory
        invalid.id = UUID()
        #expect(throws: DatabaseError.self) { try repository.save(invalid.record) }
        invalid.playerCharacterId = world.player.id
        #expect(throws: DatabaseError.self) { try repository.save(invalid.record) }
        invalid.playerCharacterId = nil
        invalid.nonPlayerCharacterId = nil
        #expect(throws: DatabaseError.self) { try repository.save(invalid.record) }
        invalid.nonPlayerCharacterId = UUID()
        #expect(throws: DatabaseError.self) { try repository.save(invalid.record) }
        let otherStory = StoryModel(title: "Other")
        try database.write { db in try otherStory.record.insert(db) }
        invalid.nonPlayerCharacterId = world.npc.id
        invalid.storyId = otherStory.id
        #expect(throws: DatabaseError.self) { try repository.save(invalid.record) }
        let sword = ItemModel(storyId: world.story.id, name: "Sword")
        try database.write { db in try sword.record.insert(db) }
        invalid.storyId = world.story.id
        invalid.itemId = sword.id
        #expect(throws: DatabaseError.self) { try repository.save(invalid.record) }
        invalid.equipmentSlot = nil
        try repository.save(invalid.record)
        // Transfer an existing entry by replacing its owner in one write.
        invalid.nonPlayerCharacterId = nil
        invalid.playerCharacterId = world.player.id
        try repository.save(invalid.record)
        #expect(try repository.get(id: invalid.id)?.playerCharacterId == world.player.id)
        try RecordRepository<NonPlayerCharacterRecord>(database: database).delete(id: world.npc.id)
        #expect(try repository.get(id: inventory.id) == nil)
        #expect(try repository.get(id: world.inventory.id) != nil)
        #expect(try repository.get(id: invalid.id) != nil)
    }

    @Test func upgradesLegacyInventoryWithoutLosingRows() throws {
        let directory = URL.temporaryDirectory.appending(path: "epoch-v1-upgrade-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appending(path: "epoch.sqlite").path
        let world = World()
        do {
            let queue = try DatabaseQueue(path: path)
            var legacyMigrator = DatabaseMigrator()
            legacyMigrator.registerMigration("v1_story_world") { db in
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
            try legacyMigrator.migrate(queue)
            try queue.write { db in
                try world.story.record.insert(db)
                try world.location.record.insert(db)
                try world.player.record.insert(db)
                try world.item.record.insert(db)
                try db.execute(sql: "INSERT INTO player_inventory (id, createdAt, updatedAt, storyId, playerCharacterId, itemId, quantity, equipmentSlot) VALUES (?, ?, ?, ?, ?, ?, ?, ?)", arguments: [world.inventory.id.uuidString, world.inventory.createdAt, world.inventory.updatedAt, world.story.id.uuidString, world.player.id.uuidString, world.item.id.uuidString, 1, "hand"])
                // Legacy NPCs have no attributes column.
                try db.execute(sql: "INSERT INTO non_player_character (id, storyId, name) VALUES (?, ?, ?)", arguments: [world.npc.id.uuidString, world.story.id.uuidString, "Keeper"])
            }
        }
        let upgraded = try DBManager(path: path)
        let inventory = try #require(try RecordRepository<PlayerInventoryRecord>(database: upgraded).get(id: world.inventory.id))
        #expect(inventory.playerCharacterId == world.player.id)
        #expect(inventory.nonPlayerCharacterId == nil)
        #expect(inventory.quantity == 1)
        #expect(inventory.equipmentSlot == "hand")
        #expect(abs(inventory.createdAt.timeIntervalSince(world.inventory.createdAt)) < 0.001)
        #expect(try RecordRepository<NonPlayerCharacterRecord>(database: upgraded).get(id: world.npc.id)?.attributes == [:])
        let npcInventory = PlayerInventoryModel(storyId: world.story.id, nonPlayerCharacterId: world.npc.id, itemId: world.item.id)
        try RecordRepository<PlayerInventoryRecord>(database: upgraded).save(npcInventory.record)
        try upgraded.read { (db: Database) throws -> Void in
            #expect(try Row.fetchAll(db, sql: "PRAGMA foreign_key_check").isEmpty)
            #expect(try PlayerInventoryRecord.fetchCount(db) == 2)
        }
    }
}
