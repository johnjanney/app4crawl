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

    private var currentJobID: String?
    private var runTask: Task<Void, Never>?

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
        runTask?.cancel()
        let config = self.config
        runTask = Task { await self.execute(config: config, baseURL: baseURL) }
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
        phase = .idle
    }

    private var lastBaseURL: URL?

    private func execute(config: CrawlConfig, baseURL: URL) async {
        lastBaseURL = baseURL
        let client = CrawlAPIClient(baseURL: baseURL)
        phase = .running(pages: 0)
        do {
            let created = config.deep
                ? try await client.startDeep(config.deepRequest())
                : try await client.startSingle(config.singleRequest())
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
    @StateObject private var controller = CrawlController()

    var body: some View {
        NavigationSplitView {
            HistoryView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        } detail: {
            content
                .navigationTitle("App4Crawl")
                .toolbar { toolbarContent }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch controller.phase {
        case .completed(let pages):
            ResultsContainer(
                pages: pages,
                selectedPage: $controller.selectedPage,
                onNewCrawl: { controller.reset() })
        default:
            CrawlConfigView(
                config: $controller.config,
                phase: controller.phase,
                onRun: { controller.run(baseURL: server.baseURL) },
                onCancel: { controller.cancel() })
        }
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
        HStack {
            Text("\(pages.count) page\(pages.count == 1 ? "" : "s") crawled")
                .font(.headline)
            Spacer()
            Button("New Crawl", systemImage: "plus", action: onNewCrawl)
        }
        .padding(12)
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
}
