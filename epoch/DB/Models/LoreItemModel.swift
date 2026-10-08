import Foundation

nonisolated struct LoreItemModel: Identifiable, Hashable, Sendable {
    var id: UUID = UUID()
    var createdAt: Date = .now
    var updatedAt: Date = .now
    var storyId: UUID
    var title: String
    var text: String = ""
    var category: String = "general"
    var keywords: [String] = []
    var isDiscovered: Bool = false
    var locationId: UUID? = nil
    var nonPlayerCharacterId: UUID? = nil
    var itemId: UUID? = nil
}

extension LoreItemModel {
    nonisolated init(record: LoreItemRecord) {
        self.id = record.id
        self.createdAt = record.createdAt
        self.updatedAt = record.updatedAt
        self.storyId = record.storyId
        self.title = record.title
        self.text = record.text
        self.category = record.category
        self.keywords = record.keywords
        self.isDiscovered = record.isDiscovered
        self.locationId = record.locationId
        self.nonPlayerCharacterId = record.nonPlayerCharacterId
        self.itemId = record.itemId
    }

    nonisolated var record: LoreItemRecord {
        LoreItemRecord(
            id: id,
            createdAt: createdAt,
            updatedAt: updatedAt,
            storyId: storyId,
            title: title,
            text: text,
            category: category,
            keywords: keywords,
            isDiscovered: isDiscovered,
            locationId: locationId,
            nonPlayerCharacterId: nonPlayerCharacterId,
            itemId: itemId
        )
    }
}
