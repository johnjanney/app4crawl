//
//  ResultExporter.swift
//  App4Crawl
//
//  Exports a crawled page to a file in Markdown, JSON, or HTML
//  (PROJECTBRIEF §5). Uses a standard save panel; nothing is written without
//  the user choosing a destination.
//

import AppKit
import Foundation
import UniformTypeIdentifiers

/// Supported export formats.
enum ExportFormat: String, CaseIterable, Identifiable {
    case markdown
    case json
    case html

    var id: String { rawValue }

    var label: String {
        switch self {
        case .markdown: return "Markdown (.md)"
        case .json: return "JSON (.json)"
        case .html: return "HTML (.html)"
        }
    }

    var fileExtension: String {
        switch self {
        case .markdown: return "md"
        case .json: return "json"
        case .html: return "html"
        }
    }

    var contentType: UTType {
        switch self {
        case .markdown: return UTType(filenameExtension: "md") ?? .plainText
        case .json: return .json
        case .html: return .html
        }
    }
}

/// Writes crawl results to disk via a save panel.
enum ResultExporter {
    /// Present a save panel and write `page` in `format`.
    @MainActor
    static func export(_ page: PageResultDTO, as format: ExportFormat) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName(for: page, format: format)
        panel.allowedContentTypes = [format.contentType]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let text = content(for: page, format: format)
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            presentError(error)
        }
    }

    /// Whether a format has content available for the given page.
    static func isAvailable(_ format: ExportFormat, for page: PageResultDTO) -> Bool {
        switch format {
        case .markdown: return (page.fitMarkdown ?? page.markdown)?.isEmpty == false
        case .json: return true
        case .html: return page.rawHtml?.isEmpty == false
        }
    }

    // MARK: - Helpers

    private static func content(for page: PageResultDTO, format: ExportFormat) -> String {
        switch format {
        case .markdown:
            return page.fitMarkdown ?? page.markdown ?? ""
        case .html:
            return page.rawHtml ?? ""
        case .json:
            if let data = try? JSONEncoder.app(pretty: true).encode(page),
               let string = String(data: data, encoding: .utf8) {
                return string
            }
            return page.extractedContent?.prettyPrinted() ?? "{}"
        }
    }

    private static func suggestedName(for page: PageResultDTO, format: ExportFormat) -> String {
        let host = URL(string: page.url)?.host ?? "result"
        let safe = host.replacingOccurrences(of: ".", with: "-")
        return "\(safe).\(format.fileExtension)"
    }

    private static func presentError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Could not export file"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }
}
