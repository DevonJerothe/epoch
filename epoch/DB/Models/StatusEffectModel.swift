import Foundation

nonisolated enum StatusEffectModifierOperation: String, Codable, Hashable, Sendable {
    case add
    case multiply
}

/// Target keys are game-defined, e.g. "attribute.stealth" or "loot.container.gold".
/// A multiplier of 1.1 increases a value by 10%; an additive value of -1 reduces it by one.
nonisolated struct StatusEffectModifier: Codable, Hashable, Sendable {
    var target: String
    var operation: StatusEffectModifierOperation
    var value: Double
}

/// An applied effect owned by one character. Nil turnsRemaining lasts until explicitly removed.
nonisolated struct StatusEffectModel: Identifiable, Hashable, Sendable {
    var id: UUID = UUID()
    var createdAt: Date = .now
    var updatedAt: Date = .now
    var storyId: UUID
    var playerCharacterId: UUID? = nil
    var nonPlayerCharacterId: UUID? = nil
    var name: String
    var description: String = ""
    var modifiers: [StatusEffectModifier] = []
    var customEffects: [String: String] = [:]
    var removalConditions: [String] = []
    var turnsRemaining: Int? = nil

    var isActive: Bool { turnsRemaining.map { $0 > 0 } ?? true }
}

extension StatusEffectModel {
    nonisolated init(record: StatusEffectRecord) {
        self.id = record.id
        self.createdAt = record.createdAt
        self.updatedAt = record.updatedAt
        self.storyId = record.storyId
        self.playerCharacterId = record.playerCharacterId
        self.nonPlayerCharacterId = record.nonPlayerCharacterId
        self.name = record.name
        self.description = record.description
        self.modifiers = record.modifiers
        self.customEffects = record.customEffects
        self.removalConditions = record.removalConditions
        self.turnsRemaining = record.turnsRemaining
    }

    nonisolated var record: StatusEffectRecord {
        StatusEffectRecord(
            id: id,
            createdAt: createdAt,
            updatedAt: updatedAt,
            storyId: storyId,
            playerCharacterId: playerCharacterId,
            nonPlayerCharacterId: nonPlayerCharacterId,
            name: name,
            description: description,
            modifiers: modifiers,
            customEffects: customEffects,
            removalConditions: removalConditions,
            turnsRemaining: turnsRemaining
        )
    }
}
