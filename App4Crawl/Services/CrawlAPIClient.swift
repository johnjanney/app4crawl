//
//  CrawlAPIClient.swift
//  App4Crawl
//
//  HTTP client for the FastAPI backend. Placeholder for Phase 1; implemented
//  in Phase 4.
//

import Foundation

/// Talks to the local FastAPI server over `127.0.0.1`.
struct CrawlAPIClient {
    /// Base URL of the running backend, e.g. `http://127.0.0.1:<port>`.
    let baseURL: URL

    init(baseURL: URL) {
        self.baseURL = baseURL
    }

    // Endpoint methods (health, single/deep crawl, status, result, stream,
    // cancel, providers) are implemented in Phase 4.
}
