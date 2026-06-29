//
//  KeychainService.swift
//  App4Crawl
//
//  Stores LLM provider API keys in the macOS Keychain via the Security
//  framework (PROJECTBRIEF §7). Keys are never written to UserDefaults, a
//  plist, or any file on disk.
//

import Foundation
import Security

/// Keychain-backed store for per-provider API keys.
struct KeychainService {
    enum KeychainError: LocalizedError {
        case unexpectedStatus(OSStatus)
        case encodingFailed

        var errorDescription: String? {
            switch self {
            case .unexpectedStatus(let status):
                let message = SecCopyErrorMessageString(status, nil) as String?
                return "Keychain error: \(message ?? "status \(status)")"
            case .encodingFailed:
                return "Could not encode the API key."
            }
        }
    }

    /// Keychain service identifier scoping these items to App4Crawl.
    private let service: String

    init(service: String? = nil) {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.app4crawl.App4Crawl"
        self.service = service ?? "\(bundleID).apikeys"
    }

    /// Base query identifying a single provider's key item.
    private func baseQuery(for provider: LLMProvider) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue,
        ]
    }

    /// Store (or replace) the key for a provider.
    func set(_ key: String, for provider: LLMProvider) throws {
        guard let data = key.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }
        // Replace any existing item to keep the operation idempotent.
        SecItemDelete(baseQuery(for: provider) as CFDictionary)

        var attributes = baseQuery(for: provider)
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// Retrieve the key for a provider, if present.
    func get(for provider: LLMProvider) -> String? {
        var query = baseQuery(for: provider)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8)
        else { return nil }
        return value
    }

    /// Delete the key for a provider. Succeeds if no key was stored.
    func delete(for provider: LLMProvider) throws {
        let status = SecItemDelete(baseQuery(for: provider) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// Whether a key is stored for a provider.
    func hasKey(for provider: LLMProvider) -> Bool {
        get(for: provider) != nil
    }
}
