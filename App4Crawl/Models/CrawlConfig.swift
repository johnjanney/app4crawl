//
//  CrawlConfig.swift
//  App4Crawl
//
//  User-facing crawl configuration, encoded into requests to the backend.
//  Placeholder for Phase 1.
//

import Foundation

/// Deep-crawl traversal strategy.
enum CrawlStrategy: String, Codable, CaseIterable {
    case bfs
    case dfs
}

/// Configuration for a single or deep crawl. Expanded in later phases.
struct CrawlConfig: Codable {
    var url: String = ""
    var deep: Bool = false
    var strategy: CrawlStrategy = .bfs
    var maxDepth: Int = 2
    var maxPages: Int = 10
}
