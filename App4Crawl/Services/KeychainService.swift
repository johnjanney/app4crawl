//
//  KeychainService.swift
//  App4Crawl
//
//  Stores LLM provider API keys in the macOS Keychain via Security framework.
//  Keys are never written to UserDefaults, plist, or any file on disk.
//  Placeholder for Phase 1; implemented in Phase 5.
//

import Foundation

/// Keychain-backed store for provider API keys.
struct KeychainService {
    /// Stores or updates the key for a provider. Implemented in Phase 5.
    func set(_ key: String, for provider: LLMProvider) {}

    /// Retrieves the key for a provider, if present. Implemented in Phase 5.
    func get(for provider: LLMProvider) -> String? { nil }

    /// Deletes the key for a provider. Implemented in Phase 5.
    func delete(for provider: LLMProvider) {}
}
