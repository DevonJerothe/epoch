import Foundation

nonisolated struct LocationModel: Identifiable, Hashable, Sendable {
    var id: UUID = UUID()
    var createdAt: Date = .now
    var updatedAt: Date = .now
    var storyId: UUID
    var name: String
    var description: String = ""
    var parentLocationId: UUID? = nil
    var isDiscovered: Bool = false
    var image: Data? = nil
}

extension LocationModel {
    nonisolated init(record: LocationRecord) {
        self.id = record.id
        self.createdAt = record.createdAt
        self.updatedAt = record.updatedAt
        self.storyId = record.storyId
        self.name = record.name
        self.description = record.description
        self.parentLocationId = record.parentLocationId
        self.isDiscovered = record.isDiscovered
        self.image = record.image
    }

    nonisolated var record: LocationRecord {
        LocationRecord(
            id: id,
            createdAt: createdAt,
            updatedAt: updatedAt,
            storyId: storyId,
            name: name,
            description: description,
            parentLocationId: parentLocationId,
            isDiscovered: isDiscovered,
            image: image
        )
    }
}
