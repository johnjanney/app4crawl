//
//  SettingsView.swift
//  App4Crawl
//
//  Preferences (⌘,): API Keys (Keychain-backed), Environment, and Appearance.
//  Placeholder for Phase 1; implemented in Phase 5.
//

import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            Text("API Keys")
                .tabItem { Label("API Keys", systemImage: "key") }
            Text("Environment")
                .tabItem { Label("Environment", systemImage: "gearshape") }
            Text("Appearance")
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
        }
        .frame(width: 480, height: 320)
    }
}

#Preview {
    SettingsView()
}
