//
//  CrawlJob.swift
//  App4Crawl
//
//  Client-side representation of a crawl job tracked by the backend.
//  Placeholder for Phase 1.
//

import Foundation

/// Lifecycle states of a crawl job, mirroring the backend `job_manager`.
enum CrawlJobStatus: String, Codable {
    case queued
    case running
    case completed
    case failed
    case cancelled
}

/// A crawl job and its current status, identified by the backend-assigned UUID.
struct CrawlJob: Identifiable, Codable {
    let id: UUID
    var status: CrawlJobStatus
    var createdAt: Date
}
