//
//  CrawlConfig.swift
//  App4Crawl
//
//  User-facing crawl configuration (the form model behind CrawlConfigView),
//  with mapping to the API request DTOs. LLM extraction is wired in Phase 5.
//

import Foundation

/// Deep-crawl traversal strategy. Wire format matches the server.
enum CrawlStrategy: String, Codable, CaseIterable, Identifiable {
    case bfs
    case dfs

    var id: String { rawValue }

    /// Plain-English label for the UI (PROJECTBRIEF §6).
    var label: String {
        switch self {
        case .bfs: return "Broad first (level by level)"
        case .dfs: return "Deep first (follow links down)"
        }
    }
}

/// Configuration for a single or deep crawl, edited in the UI.
struct CrawlConfig: Equatable {
    var url: String = ""
    var deep: Bool = false
    var strategy: CrawlStrategy = .bfs
    var maxDepth: Int = 2
    var maxPages: Int = 10

    // Output formats.
    var includeRawHtml: Bool = true
    var includeFitMarkdown: Bool = true

    // Content filtering (PROJECTBRIEF §5).
    var contentFilterType: ContentFilterType = .none
    var pruningThreshold: Double = 0.48
    var bm25Query: String = ""

    var bypassCache: Bool = false

    /// Whether the URL looks runnable (basic, non-strict check).
    var isRunnable: Bool {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://")
    }

    /// Map the form into shared crawl options.
    private func optionsDTO() -> CrawlOptionsDTO {
        var filter = ContentFilterConfigDTO(type: contentFilterType)
        switch contentFilterType {
        case .pruning:
            filter.threshold = pruningThreshold
        case .bm25:
            filter.query = bm25Query.trimmingCharacters(in: .whitespacesAndNewlines)
        case .none:
            break
        }
        return CrawlOptionsDTO(
            includeRawHtml: includeRawHtml,
            includeFitMarkdown: includeFitMarkdown,
            contentFilter: filter,
            extraction: nil,
            bypassCache: bypassCache)
    }

    /// Build the single-URL crawl request.
    func singleRequest() -> SingleCrawlRequestDTO {
        SingleCrawlRequestDTO(
            url: url.trimmingCharacters(in: .whitespacesAndNewlines),
            options: optionsDTO())
    }

    /// Build the deep-crawl request.
    func deepRequest() -> DeepCrawlRequestDTO {
        DeepCrawlRequestDTO(
            url: url.trimmingCharacters(in: .whitespacesAndNewlines),
            strategy: strategy,
            maxDepth: maxDepth,
            maxPages: maxPages,
            options: optionsDTO())
    }
}
