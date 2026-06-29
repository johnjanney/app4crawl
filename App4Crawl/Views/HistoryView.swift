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

    @State private var renamingRecord: CrawlRecord?
    @State private var renameText = ""

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
        .alert("Rename Crawl", isPresented: Binding(
            get: { renamingRecord != nil },
            set: { if !$0 { renamingRecord = nil } }
        )) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) { renamingRecord = nil }
            Button("Save") { commitRename() }
        } message: {
            Text("Give this crawl a memorable name.")
        }
    }

    private func commitRename() {
        guard var record = renamingRecord else { return }
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        record.name = trimmed.isEmpty ? nil : trimmed
        history.update(record)
        renamingRecord = nil
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
                    Text(record.displayName)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                HStack(spacing: 6) {
                    if let host = URL(string: record.url)?.host {
                        Text(host).lineLimit(1).truncationMode(.middle)
                        Text("·")
                    }
                    Text(record.date, format: .relative(presentation: .named))
                    Text("·")
                    Text("\(record.pageCount) page\(record.pageCount == 1 ? "" : "s")")
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
            Button("Rename…") {
                renameText = record.name ?? record.displayName
                renamingRecord = record
            }
            Divider()
            Button("Delete", role: .destructive) { history.delete(record) }
        }
    }
}

#Preview {
    HistoryView()
        .environmentObject(HistoryStore())
}
