import Foundation

nonisolated struct ItemModel: Identifiable, Hashable, Sendable {
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
}

extension ItemModel {
    nonisolated init(record: ItemRecord) {
        self.id = record.id
        self.createdAt = record.createdAt
        self.updatedAt = record.updatedAt
        self.storyId = record.storyId
        self.name = record.name
        self.description = record.description
        self.category = record.category
        self.rarity = record.rarity
        self.value = record.value
        self.weight = record.weight
        self.isConsumable = record.isConsumable
        self.effects = record.effects
        self.image = record.image
    }

    nonisolated var record: ItemRecord {
        ItemRecord(
            id: id,
            createdAt: createdAt,
            updatedAt: updatedAt,
            storyId: storyId,
            name: name,
            description: description,
            category: category,
            rarity: rarity,
            value: value,
            weight: weight,
            isConsumable: isConsumable,
            effects: effects,
            image: image
        )
    }
}
