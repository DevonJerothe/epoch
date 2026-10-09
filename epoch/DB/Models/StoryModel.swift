import Foundation

nonisolated struct StoryModel: Identifiable, Hashable, Sendable {
    var id: UUID = UUID()
    var createdAt: Date = .now
    var updatedAt: Date = .now
    var title: String
    var description: String = ""
    var tags: [String] = []
    var image: Data? = nil
    var storyMessages: [StoryMessageModel] = []
}

extension StoryModel {
    nonisolated init(record: StoryRecord) {
        self.id = record.id
        self.createdAt = record.createdAt
        self.updatedAt = record.updatedAt
        self.title = record.title
        self.description = record.description
        self.tags = record.tags
        self.image = record.image
    }

    nonisolated var record: StoryRecord {
        StoryRecord(
            id: id,
            createdAt: createdAt,
            updatedAt: updatedAt,
            title: title,
            description: description,
            tags: tags,
            image: image
        )
    }
}
