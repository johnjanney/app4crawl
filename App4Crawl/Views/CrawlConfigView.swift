//
//  CrawlConfigView.swift
//  App4Crawl
//
//  Single-URL and deep-crawl configuration. Simple options up front; power
//  features behind an "Advanced" disclosure. Labels use plain English, not
//  Crawl4AI parameter names (PROJECTBRIEF §6).
//

import SwiftUI

struct CrawlConfigView: View {
    @Binding var config: CrawlConfig
    let phase: CrawlPhase
    let onRun: () -> Void
    let onCancel: () -> Void

    @State private var showAdvanced = false

    private var isRunning: Bool {
        if case .running = phase { return true }
        return false
    }

    var body: some View {
        Form {
            Section("Crawl") {
                TextField("URL", text: $config.url, prompt: Text("https://example.com"))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(runIfPossible)
                Toggle("Follow links (deep crawl)", isOn: $config.deep)
            }

            if config.deep {
                deepSection
            }

            DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
                outputSection
                filterSection
                Toggle("Ignore cached results", isOn: $config.bypassCache)
            }

            Section {
                statusRow
            }
        }
        .formStyle(.grouped)
        .navigationTitle("New Crawl")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isRunning {
                    Button("Stop", role: .destructive, action: onCancel)
                } else {
                    Button("Run", action: runIfPossible)
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(!config.isRunnable)
                }
            }
        }
    }

    // MARK: Sections

    private var deepSection: some View {
        Section("Deep crawl") {
            Picker("Direction", selection: $config.strategy) {
                ForEach(CrawlStrategy.allCases) { strategy in
                    Text(strategy.label).tag(strategy)
                }
            }
            Stepper("How many levels deep: \(config.maxDepth)",
                    value: $config.maxDepth, in: 1...10)
            Stepper("Maximum pages: \(config.maxPages)",
                    value: $config.maxPages, in: 1...1000, step: 5)
        }
    }

    private var outputSection: some View {
        Section("Output") {
            Toggle("Clean, focused Markdown", isOn: $config.includeFitMarkdown)
            Toggle("Include raw HTML", isOn: $config.includeRawHtml)
        }
    }

    private var filterSection: some View {
        Section("Content filtering") {
            Picker("Filter", selection: $config.contentFilterType) {
                Text("None").tag(ContentFilterType.none)
                Text("Remove noise from content").tag(ContentFilterType.pruning)
                Text("Keep only text matching a query").tag(ContentFilterType.bm25)
            }
            switch config.contentFilterType {
            case .pruning:
                VStack(alignment: .leading) {
                    Text("Aggressiveness: \(config.pruningThreshold, format: .number.precision(.fractionLength(2)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: $config.pruningThreshold, in: 0...1)
                }
            case .bm25:
                TextField("Search query", text: $config.bm25Query,
                          prompt: Text("e.g. pricing and plans"))
                    .textFieldStyle(.roundedBorder)
            case .none:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        switch phase {
        case .idle:
            Text("Enter a URL and press Run.")
                .foregroundStyle(.secondary)
        case .running(let pages):
            HStack(spacing: 10) {
                ProgressView()
                Text(pages > 0 ? "Crawling… \(pages) page(s) so far" : "Crawling…")
                    .foregroundStyle(.secondary)
            }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        case .completed:
            EmptyView()
        }
    }

    private func runIfPossible() {
        guard config.isRunnable, !isRunning else { return }
        onRun()
    }
}

#Preview {
    CrawlConfigView(
        config: .constant(CrawlConfig(url: "https://example.com")),
        phase: .idle,
        onRun: {},
        onCancel: {})
}
