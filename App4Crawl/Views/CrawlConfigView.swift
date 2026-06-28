//
//  CrawlConfigView.swift
//  App4Crawl
//
//  Single URL and deep crawl configuration. Progressive disclosure: simple
//  options up front, advanced behind a toggle. Placeholder for Phase 1.
//

import SwiftUI

struct CrawlConfigView: View {
    @State private var url: String = ""

    var body: some View {
        Form {
            Section("Crawl") {
                TextField("URL", text: $url, prompt: Text("https://example.com"))
                Button("Run") {}
                    .disabled(url.isEmpty)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("New Crawl")
    }
}

#Preview {
    CrawlConfigView()
}
