import Foundation

nonisolated struct PlayerCharacterModel: Identifiable, Hashable, Sendable {
    var id: UUID = UUID()
    var createdAt: Date = .now
    var updatedAt: Date = .now
    var storyId: UUID
    var name: String
    var description: String = ""
    var characterClass: String = ""
    var level: Int = 1
    var experience: Int = 0
    var health: Int = 100
    var maxHealth: Int = 100
    var currency: Int = 0
    var attributes: [String: Int] = [:]
    var locationId: UUID? = nil
    var image: Data? = nil
}

extension PlayerCharacterModel {
    nonisolated init(record: PlayerCharacterRecord) {
        self.id = record.id
        self.createdAt = record.createdAt
        self.updatedAt = record.updatedAt
        self.storyId = record.storyId
        self.name = record.name
        self.description = record.description
        self.characterClass = record.characterClass
        self.level = record.level
        self.experience = record.experience
        self.health = record.health
        self.maxHealth = record.maxHealth
        self.currency = record.currency
        self.attributes = record.attributes
        self.locationId = record.locationId
        self.image = record.image
    }

    nonisolated var record: PlayerCharacterRecord {
        PlayerCharacterRecord(
            id: id,
            createdAt: createdAt,
            updatedAt: updatedAt,
            storyId: storyId,
            name: name,
            description: description,
            characterClass: characterClass,
            level: level,
            experience: experience,
            health: health,
            maxHealth: maxHealth,
            currency: currency,
            attributes: attributes,
            locationId: locationId,
            image: image
        )
    }
}
