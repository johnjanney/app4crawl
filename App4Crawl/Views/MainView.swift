//
//  MainView.swift
//  App4Crawl
//
//  Primary interface: sidebar (history/sessions) plus a content area that hosts
//  either crawl configuration or the result viewer. Placeholder for Phase 1.
//

import SwiftUI

struct MainView: View {
    var body: some View {
        NavigationSplitView {
            HistoryView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        } detail: {
            CrawlConfigView()
        }
        .navigationTitle("App4Crawl")
        .toolbar {
            ToolbarItemGroup {
                Button("New Crawl", systemImage: "plus") {}
                Button("History", systemImage: "clock") {}
            }
        }
    }
}

#Preview {
    MainView()
}
