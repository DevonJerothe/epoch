import Foundation
import Observation

/// Holds what the player is typing in Settings. Keys live here only until they are saved to
/// the Keychain; saved keys are never read back into the UI.
@MainActor
@Observable
final class SettingsViewModel {
    let configuration: AIConfigurationManager
    @ObservationIgnored private let errors: ErrorManager

    var modelDraft: String
    var decisionModelDraft: String
    var keyDrafts: [CredentialKind: String] = [:]
    /// Keys being replaced, which show the entry field although one is already stored.
    private(set) var replacing: Set<CredentialKind> = []
    private(set) var saving: Set<CredentialKind> = []
    var pendingRemoval: CredentialKind?

    init(configuration: AIConfigurationManager, errors: ErrorManager? = nil) {
        self.configuration = configuration
        self.errors = errors ?? .shared
        modelDraft = configuration.settings.model(for: configuration.settings.textProvider)
        decisionModelDraft = configuration.settings.model(for: configuration.settings.decisionProvider)
    }

    var textProvider: TextProvider { configuration.settings.textProvider }
    var decisionProvider: DecisionProvider { configuration.settings.decisionProvider }
    var imageProvider: ImageProvider { configuration.settings.imageProvider }

    /// True when the decision provider's key is the one already shown under the narrator.
    var decisionSharesNarratorKey: Bool {
        decisionProvider.credential != nil && decisionProvider.credential == textProvider.credential
    }

    func load() async {
        do {
            try await configuration.refreshCredentialStatus()
        } catch {
            errors.report(error, context: "Checking saved API keys") { [weak self] in
                await self?.load()
            }
        }
    }

    func selectTextProvider(_ provider: TextProvider) {
        // Keep what was typed for the old provider before showing the new provider's model.
        commitModel()
        configuration.selectTextProvider(provider)
        modelDraft = configuration.settings.model(for: textProvider)
    }

    func commitModel() {
        configuration.setTextModel(modelDraft, for: textProvider)
    }

    func selectDecisionProvider(_ provider: DecisionProvider) {
        commitDecisionModel()
        configuration.selectDecisionProvider(provider)
        decisionModelDraft = configuration.settings.model(for: decisionProvider)
    }

    func commitDecisionModel() {
        configuration.setDecisionModel(decisionModelDraft, for: decisionProvider)
    }

    /// Saves both model fields, e.g. when leaving Settings without pressing Done.
    func commitModels() {
        commitModel()
        commitDecisionModel()
    }

    func selectImageProvider(_ provider: ImageProvider) {
        configuration.selectImageProvider(provider)
    }

    func isStored(_ kind: CredentialKind) -> Bool {
        configuration.storedCredentials.contains(kind)
    }

    func isEditing(_ kind: CredentialKind) -> Bool {
        !isStored(kind) || replacing.contains(kind)
    }

    func canSave(_ kind: CredentialKind) -> Bool {
        !saving.contains(kind)
            && !(keyDrafts[kind] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func beginReplacing(_ kind: CredentialKind) {
        replacing.insert(kind)
    }

    func cancelReplacing(_ kind: CredentialKind) {
        replacing.remove(kind)
        keyDrafts[kind] = nil
    }

    func saveKey(for kind: CredentialKind) async {
        guard canSave(kind) else { return }
        saving.insert(kind)
        defer { saving.remove(kind) }
        do {
            try await configuration.saveCredential(keyDrafts[kind] ?? "", for: kind)
            // Drop the typed key as soon as the Keychain has it.
            keyDrafts[kind] = nil
            replacing.remove(kind)
        } catch {
            errors.report(error, context: "Saving the \(kind.displayName) API key") { [weak self] in
                await self?.saveKey(for: kind)
            }
        }
    }

    func removeKey(for kind: CredentialKind) async {
        do {
            try await configuration.removeCredential(for: kind)
            keyDrafts[kind] = nil
            replacing.remove(kind)
        } catch {
            errors.report(error, context: "Removing the \(kind.displayName) API key") { [weak self] in
                await self?.removeKey(for: kind)
            }
        }
    }
}
