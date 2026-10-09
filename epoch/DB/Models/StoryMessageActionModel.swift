import Foundation

nonisolated enum StoryMessageActionKind: String, Codable, Hashable, Sendable {
    case narrative
    case travel
    case dialogue
    case combat
    case inventory
    case quest
}

nonisolated enum StoryMessageActionStatus: String, Codable, Hashable, Sendable {
    case available
    case selected
    case resolved
    case disabled
}

nonisolated struct StoryMessageActionModel: Identifiable, Hashable, Sendable {
    var id: UUID = UUID()
    var createdAt: Date = .now
    var updatedAt: Date = .now
    var storyId: UUID
    var storyMessageId: UUID
    var title: String
    var text: String = ""
    var kind: StoryMessageActionKind = .narrative
    var status: StoryMessageActionStatus = .available
    var position: Int = 0
    var resolvedAt: Date? = nil
    var locationId: UUID? = nil
    var nonPlayerCharacterId: UUID? = nil
    var itemId: UUID? = nil
    var questId: UUID? = nil
}

extension StoryMessageActionModel {
    nonisolated init(record: StoryMessageActionRecord) {
        self.id = record.id
        self.createdAt = record.createdAt
        self.updatedAt = record.updatedAt
        self.storyId = record.storyId
        self.storyMessageId = record.storyMessageId
        self.title = record.title
        self.text = record.text
        self.kind = record.kind
        self.status = record.status
        self.position = record.position
        self.resolvedAt = record.resolvedAt
        self.locationId = record.locationId
        self.nonPlayerCharacterId = record.nonPlayerCharacterId
        self.itemId = record.itemId
        self.questId = record.questId
    }

    nonisolated var record: StoryMessageActionRecord {
        StoryMessageActionRecord(
            id: id,
            createdAt: createdAt,
            updatedAt: updatedAt,
            storyId: storyId,
            storyMessageId: storyMessageId,
            title: title,
            text: text,
            kind: kind,
            status: status,
            position: position,
            resolvedAt: resolvedAt,
            locationId: locationId,
            nonPlayerCharacterId: nonPlayerCharacterId,
            itemId: itemId,
            questId: questId
        )
    }
}
