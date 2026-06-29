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
    /// Optional user-provided name (overrides the auto-derived title).
    var name: String?

    init(config: CrawlConfig, results: [PageResultDTO], name: String? = nil,
         id: UUID = UUID(), date: Date = Date()) {
        self.id = id
        self.date = date
        self.config = config
        self.results = results
        self.name = name
    }

    /// The crawled URL (from the saved configuration).
    var url: String { config.url }

    /// Number of pages captured.
    var pageCount: Int { results.count }

    /// Whether at least one page succeeded.
    var succeeded: Bool { results.contains { $0.success } }

    /// A meaningful name: the user's override, else the page title, else the
    /// first Markdown heading, else the host.
    var displayName: String {
        CrawlRecord.resolveName(
            custom: name,
            title: results.first?.title,
            markdown: results.first?.fitMarkdown ?? results.first?.markdown,
            url: config.url)
    }

    /// Resolve a display name from the available signals.
    static func resolveName(custom: String?, title: String?, markdown: String?,
                            url: String) -> String {
        if let custom = custom?.trimmingCharacters(in: .whitespacesAndNewlines),
           !custom.isEmpty {
            return custom
        }
        if let title = title?.trimmingCharacters(in: .whitespacesAndNewlines),
           !title.isEmpty {
            return title
        }
        if let heading = firstHeading(in: markdown) {
            return heading
        }
        return URL(string: url)?.host ?? url
    }

    /// First Markdown ATX heading (`# ...`) in `markdown`, if any.
    static func firstHeading(in markdown: String?) -> String? {
        guard let markdown else { return nil }
        for rawLine in markdown.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("#") else { continue }
            let text = line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
            if !text.isEmpty { return text }
        }
        return nil
    }
}
