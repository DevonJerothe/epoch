import Foundation

nonisolated struct PlayerInventoryModel: Identifiable, Hashable, Sendable {
    var id: UUID = UUID()
    var createdAt: Date = .now
    var updatedAt: Date = .now
    var storyId: UUID
    var playerCharacterId: UUID? = nil
    var nonPlayerCharacterId: UUID? = nil
    var itemId: UUID
    var quantity: Int = 1
    var equipmentSlot: String? = nil
}

extension PlayerInventoryModel {
    nonisolated init(record: PlayerInventoryRecord) {
        self.id = record.id
        self.createdAt = record.createdAt
        self.updatedAt = record.updatedAt
        self.storyId = record.storyId
        self.playerCharacterId = record.playerCharacterId
        self.nonPlayerCharacterId = record.nonPlayerCharacterId
        self.itemId = record.itemId
        self.quantity = record.quantity
        self.equipmentSlot = record.equipmentSlot
    }

    nonisolated var record: PlayerInventoryRecord {
        PlayerInventoryRecord(
            id: id,
            createdAt: createdAt,
            updatedAt: updatedAt,
            storyId: storyId,
            playerCharacterId: playerCharacterId,
            nonPlayerCharacterId: nonPlayerCharacterId,
            itemId: itemId,
            quantity: quantity,
            equipmentSlot: equipmentSlot
        )
    }
}
