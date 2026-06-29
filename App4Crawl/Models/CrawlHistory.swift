//
//  CrawlHistory.swift
//  App4Crawl
//
//  A local record of a past crawl, used for the history log and re-running
//  (PROJECTBRIEF §5). Stored on disk under ~/.app4crawl/config; contains no
//  secrets (the API key lives only in the Keychain).
//

import Foundation

/// One past crawl: the configuration used and the results it produced.
struct CrawlRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let date: Date
    var config: CrawlConfig
    var results: [PageResultDTO]

    init(config: CrawlConfig, results: [PageResultDTO], id: UUID = UUID(), date: Date = Date()) {
        self.id = id
        self.date = date
        self.config = config
        self.results = results
    }

    /// The crawled URL (from the saved configuration).
    var url: String { config.url }

    /// Number of pages captured.
    var pageCount: Int { results.count }

    /// Whether at least one page succeeded.
    var succeeded: Bool { results.contains { $0.success } }
}
