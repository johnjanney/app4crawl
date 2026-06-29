//
//  MainView.swift
//  App4Crawl
//
//  Primary interface: sidebar (history) plus a content area that hosts either
//  crawl configuration or the result viewer (PROJECTBRIEF §6). A CrawlController
//  coordinates running crawls against the local FastAPI backend.
//

import SwiftUI

/// Lifecycle of the current crawl, surfaced to the UI.
enum CrawlPhase: Equatable {
    case idle
    case running(pages: Int)
    case completed([PageResultDTO])
    case failed(String)
}

/// Coordinates a crawl: submit, poll for completion, expose results.
@MainActor
final class CrawlController: ObservableObject {
    @Published var config = CrawlConfig()
    @Published private(set) var phase: CrawlPhase = .idle
    @Published var selectedPage: PageResultDTO?
    /// Optional user-provided name for this crawl (overrides the page title).
    @Published var crawlName: String = ""

    private var currentJobID: String?
    private var runTask: Task<Void, Never>?
    private let keychain = KeychainService()

    /// Local history store; set by the view once available.
    var historyStore: HistoryStore?

    var isBusy: Bool {
        if case .running = phase { return true }
        return false
    }

    /// Start a crawl using the running server's base URL.
    func run(baseURL: URL?) {
        guard let baseURL else {
            phase = .failed("The local server isn’t running yet.")
            return
        }
        if let problem = config.validationError {
            phase = .failed(problem)
            return
        }
        if config.extractionEnabled,
           config.extractionProvider.requiresAPIKey,
           !keychain.hasKey(for: config.extractionProvider) {
            phase = .failed(
                "Add an API key for \(config.extractionProvider.displayName) in Settings (⌘,).")
            return
        }
        runTask?.cancel()
        let config = self.config
        runTask = Task { await self.execute(config: config, baseURL: baseURL) }
    }

    /// Inject the Keychain API key (and custom base URL) into an outgoing
    /// request's extraction options. Keys are read per-run and never persisted
    /// outside the Keychain (PROJECTBRIEF §7).
    private func injectCredentials(into options: inout CrawlOptionsDTO) {
        guard var extraction = options.extraction else { return }
        let provider = extraction.llm.provider
        if provider.requiresAPIKey {
            extraction.llm.apiKey = keychain.get(for: provider)
        }
        if provider == .custom {
            extraction.llm.baseURL =
                UserDefaults.standard.string(forKey: AppDefaults.customLLMBaseURL)
        }
        options.extraction = extraction
    }

    /// Cancel the in-flight crawl (best effort).
    func cancel() {
        runTask?.cancel()
        if let jobID = currentJobID, case .running = phase {
            let baseURL = lastBaseURL
            Task {
                if let baseURL {
                    try? await CrawlAPIClient(baseURL: baseURL).cancel(jobID: jobID)
                }
            }
        }
        phase = .idle
    }

    /// Reset back to the configuration screen.
    func reset() {
        runTask?.cancel()
        currentJobID = nil
        selectedPage = nil
        crawlName = ""
        phase = .idle
    }

    /// Open a past crawl's saved results without re-running.
    func show(_ record: CrawlRecord) {
        runTask?.cancel()
        config = record.config
        crawlName = record.name ?? ""
        selectedPage = record.results.first
        phase = .completed(record.results)
    }

    /// Re-run a past crawl's configuration.
    func rerun(_ record: CrawlRecord, baseURL: URL?) {
        config = record.config
        crawlName = record.name ?? ""
        run(baseURL: baseURL)
    }

    /// The name to show for the current results (live, before it's a record).
    func resolvedName(for pages: [PageResultDTO]) -> String {
        CrawlRecord.resolveName(
            custom: crawlName,
            title: pages.first?.title,
            markdown: pages.first?.fitMarkdown ?? pages.first?.markdown,
            url: config.url)
    }

    private var lastBaseURL: URL?

    private func execute(config: CrawlConfig, baseURL: URL) async {
        lastBaseURL = baseURL
        let client = CrawlAPIClient(baseURL: baseURL)
        phase = .running(pages: 0)
        do {
            let created: JobCreatedResponseDTO
            if config.deep {
                var request = config.deepRequest()
                injectCredentials(into: &request.options)
                created = try await client.startDeep(request)
            } else {
                var request = config.singleRequest()
                injectCredentials(into: &request.options)
                created = try await client.startSingle(request)
            }
            currentJobID = created.jobId

            while !Task.isCancelled {
                try await Task.sleep(nanoseconds: 500_000_000)  // 0.5s poll
                let status = try await client.status(jobID: created.jobId)
                switch status.status {
                case .queued, .running:
                    phase = .running(pages: status.pagesCrawled)
                case .completed:
                    let result = try await client.result(jobID: created.jobId)
                    selectedPage = result.results.first
                    phase = .completed(result.results)
                    let trimmed = crawlName.trimmingCharacters(in: .whitespacesAndNewlines)
                    historyStore?.add(CrawlRecord(
                        config: config,
                        results: result.results,
                        name: trimmed.isEmpty ? nil : trimmed))
                    return
                case .failed:
                    phase = .failed(status.error ?? "The crawl failed.")
                    return
                case .cancelled:
                    phase = .idle
                    return
                }
            }
        } catch is CancellationError {
            // Left to reset()/cancel() to set state.
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}

struct MainView: View {
    @EnvironmentObject private var server: ServerManager
    @EnvironmentObject private var history: HistoryStore
    @StateObject private var controller = CrawlController()

    var body: some View {
        NavigationSplitView {
            HistoryView(
                onSelect: { controller.show($0) },
                onRerun: { controller.rerun($0, baseURL: server.baseURL) })
                .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        } detail: {
            VStack(spacing: 0) {
                if !server.isRunning {
                    serverBanner
                }
                content
            }
            .navigationTitle("App4Crawl")
            .toolbar { toolbarContent }
        }
        .onAppear { controller.historyStore = history }
        .onReceive(NotificationCenter.default.publisher(for: .newCrawl)) { _ in
            controller.reset()
        }
        .onReceive(NotificationCenter.default.publisher(for: .runCrawl)) { _ in
            if !controller.isBusy { controller.run(baseURL: server.baseURL) }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch controller.phase {
        case .completed(let pages):
            ResultsContainer(
                name: controller.resolvedName(for: pages),
                pages: pages,
                selectedPage: $controller.selectedPage,
                onNewCrawl: { controller.reset() })
        default:
            CrawlConfigView(
                config: $controller.config,
                name: $controller.crawlName,
                phase: controller.phase,
                onRun: { controller.run(baseURL: server.baseURL) },
                onCancel: { controller.cancel() })
        }
    }

    /// Banner shown while the local backend is starting or after a start error.
    private var serverBanner: some View {
        HStack(spacing: 8) {
            if let error = server.lastError {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text("Local server problem: \(error)")
            } else {
                ProgressView().controlSize(.small)
                Text("Starting the local crawl server…")
            }
            Spacer()
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button("New Crawl", systemImage: "plus") { controller.reset() }
        }
        ToolbarItem(placement: .primaryAction) {
            serverStatus
        }
    }

    /// Subtle indicator of backend connectivity (PROJECTBRIEF §4/§6).
    private var serverStatus: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(server.isRunning ? Color.green : Color.secondary)
                .frame(width: 8, height: 8)
            Text(server.isRunning ? "Connected" : "Starting…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .help(server.isRunning
            ? "Connected to the local crawl server."
            : "Waiting for the local crawl server.")
    }
}

/// Shows crawl results: a page list when a deep crawl returned several pages,
/// plus the detailed result viewer for the selected page.
struct ResultsContainer: View {
    let name: String
    let pages: [PageResultDTO]
    @Binding var selectedPage: PageResultDTO?
    let onNewCrawl: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if pages.count > 1 {
                HSplitView {
                    pageList
                        .frame(minWidth: 220, idealWidth: 260, maxWidth: 360)
                    detail
                }
            } else {
                detail
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text("\(pages.count) page\(pages.count == 1 ? "" : "s") crawled")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            exportMenu
            Button("New Crawl", systemImage: "plus", action: onNewCrawl)
        }
        .padding(12)
    }

    /// Export the currently selected page as Markdown, JSON, or HTML.
    @ViewBuilder
    private var exportMenu: some View {
        if let page = selectedPage ?? pages.first {
            Menu {
                ForEach(ExportFormat.allCases) { format in
                    Button(format.label) {
                        ResultExporter.export(page, as: format, suggestedName: name)
                    }
                    .disabled(!ResultExporter.isAvailable(format, for: page))
                }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    private var pageList: some View {
        List(pages, selection: Binding(
            get: { selectedPage?.id },
            set: { id in selectedPage = pages.first { $0.id == id } }
        )) { page in
            VStack(alignment: .leading, spacing: 2) {
                Text(page.url)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Label(
                    page.success ? "OK" : "Failed",
                    systemImage: page.success ? "checkmark.circle" : "xmark.circle")
                    .font(.caption)
                    .foregroundStyle(page.success ? .green : .red)
            }
            .tag(page.id)
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let page = selectedPage ?? pages.first {
            ResultView(result: page)
        } else {
            Text("Select a page").foregroundStyle(.secondary)
        }
    }
}

#Preview {
    MainView()
        .environmentObject(ServerManager())
        .environmentObject(HistoryStore())
}
