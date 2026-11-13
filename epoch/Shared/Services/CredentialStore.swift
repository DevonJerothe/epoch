import Foundation
import os
import Security

/// One stored API key. The raw value is the Keychain account name; do not change it.
nonisolated enum CredentialKind: String, CaseIterable, Hashable, Sendable {
    case openAI = "openai"
    case openRouter = "openrouter"
    case replicate
    /// TypeSafe's direct Jev API, used for decisions only.
    case jev

    var displayName: String {
        switch self {
        case .openAI: "OpenAI"
        case .openRouter: "OpenRouter"
        case .replicate: "Replicate"
        case .jev: "Jev"
        }
    }
}

/// Secure storage for API keys. Implementations must do their work off the caller's actor.
nonisolated protocol CredentialStore: Sendable {
    /// Returns `nil` when nothing is stored.
    func read(_ kind: CredentialKind) async throws -> String?
    func save(_ value: String, for kind: CredentialKind) async throws
    /// Succeeds when nothing was stored.
    func remove(_ kind: CredentialKind) async throws
}

nonisolated struct KeychainError: LocalizedError, Equatable {
    enum Operation: String, Sendable {
        case read, save, remove
    }

    let operation: Operation
    let status: OSStatus

    var errorDescription: String? {
        let detail = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
        return "Couldn't \(operation.rawValue) the API key in the Keychain: \(detail)"
    }
}

/// Stores keys as generic passwords that stay on this device: they are readable only while it
/// is unlocked, and are excluded from iCloud Keychain and from backups restored elsewhere.
nonisolated struct KeychainCredentialStore: CredentialStore {
    private let service: String

    init(service: String = (Bundle.main.bundleIdentifier ?? "com.devonjerothe.epoch") + ".credentials") {
        self.service = service
    }

    @concurrent
    func read(_ kind: CredentialKind) async throws -> String? {
        var query = baseQuery(for: kind)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError(operation: .read, status: status) }
        guard let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
            throw KeychainError(operation: .read, status: errSecDecode)
        }
        return value
    }

    @concurrent
    func save(_ value: String, for kind: CredentialKind) async throws {
        let attributes: [String: Any] = [
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        var status = SecItemUpdate(baseQuery(for: kind) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let item = baseQuery(for: kind).merging(attributes) { _, new in new }
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError(operation: .save, status: status) }
    }

    @concurrent
    func remove(_ kind: CredentialKind) async throws {
        let status = SecItemDelete(baseQuery(for: kind) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(operation: .remove, status: status)
        }
    }

    private func baseQuery(for kind: CredentialKind) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: kind.rawValue,
            kSecAttrSynchronizable as String: false,
        ]
    }
}

/// Non-persistent storage for tests and previews.
nonisolated final class InMemoryCredentialStore: CredentialStore, Sendable {
    private let values: OSAllocatedUnfairLock<[CredentialKind: String]>

    init(_ values: [CredentialKind: String] = [:]) {
        self.values = OSAllocatedUnfairLock(initialState: values)
    }

    func read(_ kind: CredentialKind) async throws -> String? {
        values.withLock { $0[kind] }
    }

    func save(_ value: String, for kind: CredentialKind) async throws {
        values.withLock { $0[kind] = value }
    }

    func remove(_ kind: CredentialKind) async throws {
        values.withLock { $0[kind] = nil }
    }
}
