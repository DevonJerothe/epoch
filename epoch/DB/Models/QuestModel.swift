import Foundation

nonisolated enum QuestStatus: String, Codable, Hashable, Sendable {
    case available
    case active
    case completed
    case failed
    case abandoned
}

nonisolated struct QuestModel: Identifiable, Hashable, Sendable {
    var id: UUID = UUID()
    var createdAt: Date = .now
    var updatedAt: Date = .now
    var storyId: UUID
    var title: String
    var description: String = ""
    var status: QuestStatus = .available
    var objectives: [QuestObjective] = []
    var rewardExperience: Int = 0
    var rewardCurrency: Int = 0
    var giverId: UUID? = nil
    var locationId: UUID? = nil
    var playerCharacterId: UUID? = nil
    var completedAt: Date? = nil
}

extension QuestModel {
    nonisolated init(record: QuestRecord) {
        self.id = record.id
        self.createdAt = record.createdAt
        self.updatedAt = record.updatedAt
        self.storyId = record.storyId
        self.title = record.title
        self.description = record.description
        self.status = record.status
        self.objectives = record.objectives
        self.rewardExperience = record.rewardExperience
        self.rewardCurrency = record.rewardCurrency
        self.giverId = record.giverId
        self.locationId = record.locationId
        self.playerCharacterId = record.playerCharacterId
        self.completedAt = record.completedAt
    }

    nonisolated var record: QuestRecord {
        QuestRecord(
            id: id,
            createdAt: createdAt,
            updatedAt: updatedAt,
            storyId: storyId,
            title: title,
            description: description,
            status: status,
            objectives: objectives,
            rewardExperience: rewardExperience,
            rewardCurrency: rewardCurrency,
            giverId: giverId,
            locationId: locationId,
            playerCharacterId: playerCharacterId,
            completedAt: completedAt
        )
    }
}

/// Embedded in a quest's JSON objectives column; does not require another table.
nonisolated struct QuestObjective: Codable, Identifiable, Hashable, Sendable {
    var id: UUID = UUID()
    var description: String
    var progress: Int = 0
    var target: Int = 1

    var isCompleted: Bool { progress >= target }
}
