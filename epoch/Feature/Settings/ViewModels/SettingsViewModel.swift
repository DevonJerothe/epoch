import Foundation
import Observation

/// Holds what the player is typing in Settings. Keys live here only until they are saved to
/// the Keychain; saved keys are never read back into the UI.
@MainActor
@Observable
final class SettingsViewModel {
    let configuration: AIConfigurationManager
    @ObservationIgnored private let errors: ErrorManager

    var keyDrafts: [CredentialKind: String] = [:]
    /// Keys being replaced, which show the entry field although one is already stored.
    private(set) var replacing: Set<CredentialKind> = []
    private(set) var saving: Set<CredentialKind> = []
    var pendingRemoval: CredentialKind?

    init(configuration: AIConfigurationManager, errors: ErrorManager? = nil) {
        self.configuration = configuration
        self.errors = errors ?? .shared
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
        configuration.selectTextProvider(provider)
    }

    func selectDecisionProvider(_ provider: DecisionProvider) {
        configuration.selectDecisionProvider(provider)
    }

    func selectedModel(for role: ModelRole) -> String {
        configuration.selectedModel(for: role)
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

    func isSaving(_ kind: CredentialKind) -> Bool {
        saving.contains(kind)
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
