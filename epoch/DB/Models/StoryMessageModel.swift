import Foundation

nonisolated public enum MessageActor: Int, Codable, Hashable, Sendable {
    case user = 0
    case bot = 1
}

nonisolated public enum MessageStatus: Int, Codable, Hashable, Sendable {
    case loading = 0
    case thinking = 1
    case streaming = 2
    case done = 3
}

nonisolated struct StoryMessageModel: Identifiable, Hashable, Sendable {
    var id: UUID = UUID()
    var createdAt: Date = .now
    var updatedAt: Date = .now
    var storyId: UUID
    var actor: MessageActor
    var status: MessageStatus = .done
    var text: String = ""
    var messageImage: Data? = nil
    var tokenCount: Int = 0
    var position: Int = 0
    var actions: [StoryMessageActionModel] = []
}

extension StoryMessageModel {
    nonisolated init(record: StoryMessageRecord) {
        self.id = record.id
        self.createdAt = record.createdAt
        self.updatedAt = record.updatedAt
        self.storyId = record.storyId
        self.actor = record.actor
        self.status = record.status
        self.text = record.text
        self.messageImage = record.messageImage
        self.tokenCount = record.tokenCount
        self.position = record.position
    }

    nonisolated var record: StoryMessageRecord {
        StoryMessageRecord(
            id: id,
            createdAt: createdAt,
            updatedAt: updatedAt,
            storyId: storyId,
            actor: actor,
            status: status,
            text: text,
            messageImage: messageImage,
            tokenCount: tokenCount,
            position: position
        )
    }
}
