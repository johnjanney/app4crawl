//
//  LLMProvider.swift
//  App4Crawl
//
//  Supported LLM providers for extraction. Placeholder for Phase 1.
//

import Foundation

/// LLM providers supported in v1. `ollama` is local and needs no key;
/// `custom` supplies its own base URL and key.
enum LLMProvider: String, Codable, CaseIterable, Identifiable {
    case openai
    case anthropic
    case gemini
    case ollama
    case custom

    var id: String { rawValue }

    /// Whether this provider requires an API key.
    var requiresAPIKey: Bool {
        self != .ollama
    }

    /// Human-readable display name.
    var displayName: String {
        switch self {
        case .openai: return "OpenAI"
        case .anthropic: return "Anthropic"
        case .gemini: return "Gemini"
        case .ollama: return "Ollama (local)"
        case .custom: return "Custom"
        }
    }

    /// Suggested model identifiers for the model picker (mirrors the server's
    /// `/providers` catalog; the field remains free-text).
    var suggestedModels: [String] {
        switch self {
        case .openai: return ["gpt-4o", "gpt-4o-mini"]
        case .anthropic: return ["claude-3-5-sonnet-20241022", "claude-3-5-haiku-20241022"]
        case .gemini: return ["gemini-1.5-pro", "gemini-1.5-flash"]
        case .ollama: return ["llama3.3", "qwen2.5"]
        case .custom: return []
        }
    }
}
