//
//  ResultView.swift
//  App4Crawl
//
//  Result viewer with Markdown, JSON, and raw HTML tabs, plus export.
//  Placeholder for Phase 1; implemented in Phase 4.
//

import SwiftUI

struct ResultView: View {
    var body: some View {
        TabView {
            Text("Markdown output")
                .tabItem { Label("Markdown", systemImage: "doc.plaintext") }
            Text("JSON output")
                .tabItem { Label("JSON", systemImage: "curlybraces") }
            Text("Raw HTML")
                .tabItem { Label("HTML", systemImage: "chevron.left.forwardslash.chevron.right") }
        }
        .padding()
    }
}

#Preview {
    ResultView()
}
