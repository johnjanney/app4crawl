//
//  ResultView.swift
//  App4Crawl
//
//  Result viewer with Markdown (rendered), JSON tree, and raw HTML tabs
//  (PROJECTBRIEF §6). Export is added in Phase 6.
//

import SwiftUI

struct ResultView: View {
    let result: PageResultDTO

    var body: some View {
        TabView {
            markdownTab
                .tabItem { Label("Markdown", systemImage: "doc.plaintext") }
            jsonTab
                .tabItem { Label("JSON", systemImage: "curlybraces") }
            htmlTab
                .tabItem { Label("HTML", systemImage: "chevron.left.forwardslash.chevron.right") }
        }
        .padding()
    }

    // MARK: Tabs

    @ViewBuilder
    private var markdownTab: some View {
        if let markdown = result.fitMarkdown ?? result.markdown, !markdown.isEmpty {
            MarkdownView(markdown: markdown)
        } else {
            EmptyTab(message: "No Markdown content for this page.")
        }
    }

    @ViewBuilder
    private var jsonTab: some View {
        if let extracted = result.extractedContent {
            ScrollView {
                JSONTreeView(key: "root", value: extracted, isExpanded: true)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .textSelection(.enabled)
        } else {
            EmptyTab(message: "No extracted JSON. Enable LLM extraction to populate this tab.")
        }
    }

    @ViewBuilder
    private var htmlTab: some View {
        if let html = result.rawHtml, !html.isEmpty {
            ScrollView([.vertical, .horizontal]) {
                Text(html)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
        } else {
            EmptyTab(message: "Raw HTML was not captured for this page.")
        }
    }
}

/// Simple placeholder shown when a tab has no content.
private struct EmptyTab: View {
    let message: String
    var body: some View {
        VStack {
            Image(systemName: "tray")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Markdown rendering

/// Lightweight, dependency-free Markdown renderer. Handles headings, bullet
/// lists, fenced code blocks, and inline formatting within paragraphs. A richer
/// renderer can be swapped in later without changing call sites.
struct MarkdownView: View {
    let markdown: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    view(for: block)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
            .padding(4)
        }
    }

    private enum Block {
        case heading(level: Int, text: String)
        case bullet(text: String)
        case code(text: String)
        case paragraph(text: String)
    }

    /// Parse the document into renderable blocks.
    private var blocks: [Block] {
        var result: [Block] = []
        var inCode = false
        var codeLines: [String] = []

        for line in markdown.components(separatedBy: "\n") {
            if line.hasPrefix("```") {
                if inCode {
                    result.append(.code(text: codeLines.joined(separator: "\n")))
                    codeLines = []
                }
                inCode.toggle()
                continue
            }
            if inCode {
                codeLines.append(line)
                continue
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            if let heading = headingLevel(trimmed) {
                result.append(.heading(level: heading.level, text: heading.text))
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                result.append(.bullet(text: String(trimmed.dropFirst(2))))
            } else {
                result.append(.paragraph(text: trimmed))
            }
        }
        if inCode, !codeLines.isEmpty {
            result.append(.code(text: codeLines.joined(separator: "\n")))
        }
        return result
    }

    private func headingLevel(_ line: String) -> (level: Int, text: String)? {
        var level = 0
        for character in line {
            if character == "#" { level += 1 } else { break }
        }
        guard level > 0, level <= 6, line.dropFirst(level).hasPrefix(" ") else { return nil }
        let text = String(line.dropFirst(level)).trimmingCharacters(in: .whitespaces)
        return (level, text)
    }

    @ViewBuilder
    private func view(for block: Block) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(inline(text))
                .font(headingFont(level))
                .bold()
        case .bullet(let text):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("•")
                Text(inline(text))
            }
        case .code(let text):
            Text(text)
                .font(.system(.caption, design: .monospaced))
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        case .paragraph(let text):
            Text(inline(text))
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .title
        case 2: return .title2
        case 3: return .title3
        default: return .headline
        }
    }

    /// Render inline Markdown (bold/italic/links/code) within a line.
    private func inline(_ text: String) -> AttributedString {
        if let attributed = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return attributed
        }
        return AttributedString(text)
    }
}

// MARK: - JSON tree

/// Recursive, collapsible view over a `JSONValue`.
struct JSONTreeView: View {
    let key: String
    let value: JSONValue
    @State private var expanded: Bool

    init(key: String, value: JSONValue, isExpanded: Bool = false) {
        self.key = key
        self.value = value
        _expanded = State(initialValue: isExpanded)
    }

    var body: some View {
        switch value {
        case .object(let dictionary):
            container(children: dictionary.sorted { $0.key < $1.key }.map { ($0.key, $0.value) })
        case .array(let items):
            container(children: items.enumerated().map { ("[\($0.offset)]", $0.element) })
        default:
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(key).foregroundStyle(.secondary)
                Text(value.scalarDescription)
            }
            .font(.system(.body, design: .monospaced))
        }
    }

    @ViewBuilder
    private func container(children: [(String, JSONValue)]) -> some View {
        DisclosureGroup(isExpanded: $expanded) {
            ForEach(Array(children.enumerated()), id: \.offset) { _, child in
                JSONTreeView(key: child.0, value: child.1)
                    .padding(.leading, 12)
            }
        } label: {
            HStack(spacing: 6) {
                Text(key).foregroundStyle(.secondary)
                Text(value.scalarDescription).foregroundStyle(.tertiary)
            }
            .font(.system(.body, design: .monospaced))
        }
    }
}

#Preview {
    ResultView(result: PageResultDTO(
        url: "https://example.com",
        success: true,
        statusCode: 200,
        markdown: "# Example\n\nThis is **bold** text.\n\n- one\n- two",
        fitMarkdown: nil,
        rawHtml: "<html><body>Hi</body></html>",
        extractedContent: .object(["title": .string("Example"), "count": .number(3)]),
        error: nil))
}
