//
//  HistoryView.swift
//  App4Crawl
//
//  Local crawl history with re-run capability (PROJECTBRIEF §5). Shown in the
//  sidebar; selecting a record opens its results, and each row can be re-run,
//  exported, or deleted.
//

import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var history: HistoryStore

    /// Open a record's saved results.
    var onSelect: (CrawlRecord) -> Void = { _ in }
    /// Re-run a record's configuration.
    var onRerun: (CrawlRecord) -> Void = { _ in }

    var body: some View {
        List {
            Section("History") {
                if history.records.isEmpty {
                    Text("No crawls yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(history.records) { record in
                        row(record)
                    }
                }
            }
        }
        .toolbar {
            if !history.records.isEmpty {
                ToolbarItem(placement: .automatic) {
                    Button("Clear History", systemImage: "trash") { history.clear() }
                }
            }
        }
    }

    private func row(_ record: CrawlRecord) -> some View {
        Button {
            onSelect(record)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: record.succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(record.succeeded ? .green : .red)
                        .font(.caption)
                    Text(displayURL(record.url))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                HStack(spacing: 6) {
                    Text(record.date, format: .relative(presentation: .named))
                    Text("·")
                    Text("\(record.pageCount) page\(record.pageCount == 1 ? "" : "s")")
                    if record.config.deep {
                        Text("·")
                        Text(record.config.strategy.rawValue.uppercased())
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Open Results") { onSelect(record) }
            Button("Re-run") { onRerun(record) }
            Divider()
            Button("Delete", role: .destructive) { history.delete(record) }
        }
    }

    private func displayURL(_ raw: String) -> String {
        URL(string: raw)?.host ?? raw
    }
}

#Preview {
    HistoryView()
        .environmentObject(HistoryStore())
}
