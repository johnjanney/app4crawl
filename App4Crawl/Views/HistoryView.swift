//
//  HistoryView.swift
//  App4Crawl
//
//  Local crawl history with re-run capability. Placeholder for Phase 1;
//  implemented in Phase 6.
//

import SwiftUI

struct HistoryView: View {
    var body: some View {
        List {
            Section("History") {
                Text("No crawls yet")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    HistoryView()
}
