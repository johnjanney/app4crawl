//
//  APIModels.swift
//  App4Crawl
//
//  Codable request/response types mirroring the FastAPI server's Pydantic
//  models (server/models.py). JSON uses snake_case; the client configures
//  key conversion so these stay camelCase. Enums from CrawlConfig/CrawlJob/
//  LLMProvider are reused where the wire format matches.
//

import Foundation

// MARK: - Shared enums (wire format matches server)

/// Content filter applied to crawl output (PROJECTBRIEF §5).
enum ContentFilterType: String, Codable, CaseIterable {
    case none
    case pruning
    case bm25
}

/// LLM extraction mode (PROJECTBRIEF §5).
enum ExtractionType: String, Codable, CaseIterable {
    case schema
    case instruction
}

// MARK: - Request payloads

struct ContentFilterConfigDTO: Codable, Equatable {
    var type: ContentFilterType = .none
    var threshold: Double = 0.48
    var query: String?
}

struct LLMConfigDTO: Codable, Equatable {
    var provider: LLMProvider
    var model: String
    var apiKey: String?
    var baseURL: String?

    private enum CodingKeys: String, CodingKey {
        case provider, model
        case apiKey
        case baseURL = "baseUrl"  // -> base_url after snake_case conversion
    }
}

struct ExtractionConfigDTO: Codable, Equatable {
    var type: ExtractionType
    var llm: LLMConfigDTO
    var schemaDefinition: JSONValue?
    var instruction: String?
}

struct CrawlOptionsDTO: Codable, Equatable {
    var includeRawHtml: Bool = true
    var includeFitMarkdown: Bool = true
    var contentFilter: ContentFilterConfigDTO = .init()
    var extraction: ExtractionConfigDTO?
    var bypassCache: Bool = false
}

struct SingleCrawlRequestDTO: Codable, Equatable {
    var url: String
    var options: CrawlOptionsDTO = .init()
}

struct DeepCrawlRequestDTO: Codable, Equatable {
    var url: String
    var strategy: CrawlStrategy = .bfs
    var maxDepth: Int = 2
    var maxPages: Int = 10
    var options: CrawlOptionsDTO = .init()
}

// MARK: - Response payloads

struct HealthResponseDTO: Codable, Equatable {
    var status: String
    var appVersion: String
    var crawl4aiVersion: String?
    var crawl4aiAvailable: Bool
}

struct JobCreatedResponseDTO: Codable, Equatable {
    var jobId: String
    var status: CrawlJobStatus
}

struct JobStatusResponseDTO: Codable, Equatable {
    var jobId: String
    var status: CrawlJobStatus
    var createdAt: Double
    var updatedAt: Double
    var pagesCrawled: Int
    var error: String?
}

struct PageResultDTO: Codable, Equatable, Identifiable {
    var url: String
    var success: Bool
    var statusCode: Int?
    var markdown: String?
    var fitMarkdown: String?
    var rawHtml: String?
    var extractedContent: JSONValue?
    var error: String?

    /// Stable identity for SwiftUI lists (URL is unique within a job result).
    var id: String { url }
}

struct JobResultResponseDTO: Codable, Equatable {
    var jobId: String
    var status: CrawlJobStatus
    var results: [PageResultDTO]
    var error: String?
}

struct ProviderInfoDTO: Codable, Equatable, Identifiable {
    var id: LLMProvider
    var displayName: String
    var requiresApiKey: Bool
    var suggestedModels: [String]
}

struct ProvidersResponseDTO: Codable, Equatable {
    var providers: [ProviderInfoDTO]
}
