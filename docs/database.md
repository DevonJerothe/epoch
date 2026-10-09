# Epoch database

Epoch stores its local story worlds in `Documents/epoch.sqlite` using GRDB 7.11.1, a serialized `DatabaseQueue`, foreign-key enforcement, and WAL journaling. `DBManager.shared` opens and migrates the database at app startup. Startup failure displays a retry screen, and repository failures propagate to their caller. `DBManager(path: ":memory:")` creates an isolated database for tests and previews.

`DatabaseMigrations` registers `v1_story_world`, calling record-owned declarative migration functions in dependency order. It creates the complete schema, including player/NPC inventory ownership, NPC attributes, and status effects. Table columns, constraints, relationships, and indexes are defined alongside their record. During development, builds use fresh databases; the initial migration does not upgrade earlier development schemas. Add new named migrations for future schema changes; do not edit a migration once released. GRDB also maintains its own migration bookkeeping table.

## Tables

All records have a UUID primary key and `createdAt`/`updatedAt` dates. UUIDs, including foreign keys, are encoded as uppercase text. Every RPG record and message belongs to a story. Composite foreign keys enforce that linked records belong to the same story, including when existing records are updated.

| Table | Stored data and relationships |
| --- | --- |
| `story` | Title, description, tags, image; owns the story world and message history. |
| `story_message` | Story, actor, generation status, text, image, token count, ordering position; owns actions. |
| `player_character` | Story, name, description, class, level, experience, current/max health, currency, attributes, image, optional current location. A story can contain multiple players. |
| `player_inventory` | Story, exactly one player or NPC owner, item, positive quantity, optional equipment slot. One stack per owner/item pair. Equipped entries contain one item, with one equipped entry per slot per owner. The existing model/record/table names remain valid for both owner types. |
| `item` | Story, name, description, category, rarity, value, weight, consumable flag, effects, image. Each item is a story-local definition; inventory tracks ownership and quantity. |
| `non_player_character` | Story, name, description, role, disposition, attributes, alive flag, image, optional location; has inventory and status-effect associations. |
| `status_effect` | Story, exactly one player or NPC owner, name, description, numeric modifiers, custom effects, removal conditions, optional remaining turns. Both character records expose a `statusEffects` association. |
| `location` | Story, name, description, discovered flag, image, optional parent location for regions/buildings/rooms. A location cannot directly parent itself. |
| `quest` | Story, title, description, status, objectives, experience/currency rewards, completion date; optional giver NPC, location, and assigned player. |
| `lore_item` | Story, title, text, category, keywords, discovered flag; optional location, NPC, and item links. |
| `story_message_action` | Story, owning message, title, text, kind, status, ordering position, resolution date; optional location, NPC, item, and quest targets. Position is unique within a message. |

Tags, keywords, character attributes, item effects, and quest objectives are Codable JSON columns. Arrays and dictionaries are validated as JSON of the expected shape by SQLite. Quest objectives are embedded values with stable IDs, descriptions, progress, and targets. Categories, rarity, character classes, and attributes stay flexible for different RPG settings. Message actors/statuses, quest statuses, and action kinds/statuses use explicit enums with database checks.

## Deletion and updates

- Deleting a story cascades through its world, messages, and actions.
- Deleting a player or NPC deletes its inventory entries and applied status effects. Deleting an item deletes its inventory entries.
- Deleting a message deletes its actions.
- Deleting an optional target (location, NPC, item, quest, or assigned player) clears that reference and preserves the referencing record.
- Health, levels, rewards, currency, token counts, weights, ordering positions, and inventory quantities have database constraints.
- Repositories refresh `updatedAt` when saving. Direct GRDB writes must maintain timestamps themselves.

Foreign-key indexes support relationship queries. Additional indexes support ordered messages/actions, quest status queries, and equipment-slot uniqueness. GRDB associations specify foreign keys explicitly because the schema has both individual and composite relationships.

## Access

Models are UI/domain values. Their `record` property converts to a database record, and `init(record:)` converts back. All models and records are Sendable; database conversions are nonisolated. Models use UUIDs for relationship IDs, replacing the initial message stub's empty string ID.

```swift
let story = StoryModel(title: "The Forgotten Kingdom")
let stories = StoryRepository()
try stories.save(story)

let player = PlayerCharacterModel(storyId: story.id, name: "Ari")
let players = RecordRepository<PlayerCharacterRecord>()
let storedPlayer = try players.save(player.record)
let loadedPlayer = PlayerCharacterModel(record: storedPlayer)

let inventory = try DBManager.shared.read { db in
    try storedPlayer.request(for: PlayerCharacterRecord.inventory).fetchAll(db)
}
```

`RecordRepository<Record>` provides get-all, UUID lookup, save, and delete for every table. Use `DBManager.write` for operations that change several records together, such as transferring items or applying a quest reward; GRDB rolls back the transaction on failure.

`StoryRepository.getAll()` loads story summaries without messages. `get(id:)` loads a consistent snapshot of a story, its ordered messages, and each message's ordered actions. `save(_:)` atomically upserts the supplied story/messages/actions, validates their ownership, and preserves omitted children. Delete children explicitly through their typed repository. Set message/action positions when composing history and choices.

The schema stores game state; it does not execute combat, rewards, action effects, or discovery rules. Quest completion dates and objective progress are managed by game logic. No seed rows or invented campaign content are created.

## Status effects

An applied effect is a row in `status_effect`, rather than a shared definition. The same effect name can be applied independently to different characters, with different durations or modifiers. Exactly one owner must be present, and that owner must belong to the effect's story.

```swift
let soaked = StatusEffectModel(
    storyId: story.id,
    playerCharacterId: player.id,
    name: "Soaked",
    modifiers: [StatusEffectModifier(target: "attribute.stealth", operation: .add, value: -1)],
    removalConditions: ["drying_off"],
    turnsRemaining: 3
)
try RecordRepository<StatusEffectRecord>().save(soaked.record)

let goldenFingers = StatusEffectModel(
    storyId: story.id,
    playerCharacterId: player.id,
    name: "Golden Fingers",
    modifiers: [StatusEffectModifier(target: "loot.container.gold", operation: .multiply, value: 1.1)]
)
```

`target` is a game-defined key; `.add` changes its value by the stated amount and `.multiply` uses a factor (1.1 means 10% more). `customEffects` stores named custom behavior descriptions; `removalConditions` stores event keys such as `drying_off`. Numeric modifiers and custom behaviors remain data for the game engine to interpret, without mutating base attributes when saving an effect.

`turnsRemaining == nil` lasts until explicitly removed; zero is expired (`StatusEffectModel.isActive == false`), and negative values are rejected. Game logic decrements durations, removes effects when a removal condition occurs, and filters expired effects when applying modifiers. Persistence does not automatically advance turns or execute effects.

Use either character record's `request(for: ...statusEffects)` or `request(for: ...inventory)` to fetch owned effects/items. NPCs have the same flexible attributes dictionary as players. Inventory ownership can be transferred by setting the old owner to nil and the new owner ID in a single save. Stack and equipment-slot uniqueness are enforced separately for player and NPC owners.
