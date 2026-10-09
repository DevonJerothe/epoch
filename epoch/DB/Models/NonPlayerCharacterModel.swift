import Foundation

nonisolated struct NonPlayerCharacterModel: Identifiable, Hashable, Sendable {
    var id: UUID = UUID()
    var createdAt: Date = .now
    var updatedAt: Date = .now
    var storyId: UUID
    var name: String
    var description: String = ""
    var role: String = ""
    var disposition: String = "neutral"
    var attributes: [String: Int] = [:]
    var isAlive: Bool = true
    var locationId: UUID? = nil
    var image: Data? = nil
}

extension NonPlayerCharacterModel {
    nonisolated init(record: NonPlayerCharacterRecord) {
        self.id = record.id
        self.createdAt = record.createdAt
        self.updatedAt = record.updatedAt
        self.storyId = record.storyId
        self.name = record.name
        self.description = record.description
        self.role = record.role
        self.disposition = record.disposition
        self.attributes = record.attributes
        self.isAlive = record.isAlive
        self.locationId = record.locationId
        self.image = record.image
    }

    nonisolated var record: NonPlayerCharacterRecord {
        NonPlayerCharacterRecord(
            id: id,
            createdAt: createdAt,
            updatedAt: updatedAt,
            storyId: storyId,
            name: name,
            description: description,
            role: role,
            disposition: disposition,
            attributes: attributes,
            isAlive: isAlive,
            locationId: locationId,
            image: image
        )
    }
}
