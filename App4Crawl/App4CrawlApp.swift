//
//  App4CrawlApp.swift
//  App4Crawl
//
//  App entry point. Owns the FastAPI server lifecycle and routes between the
//  onboarding flow and the main UI.
//

import SwiftUI

@main
struct App4CrawlApp: App {
    /// Manages the FastAPI backend subprocess (launch on start, terminate on quit).
    @StateObject private var serverManager = ServerManager()

    /// Detects the Python / Crawl4AI environment to decide onboarding vs. main UI.
    @StateObject private var environmentChecker = EnvironmentChecker()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(serverManager)
                .environmentObject(environmentChecker)
        }
        .windowStyle(.titleBar)
        .commands {
            // Native menu commands (New Crawl, etc.) added in later phases.
        }

        Settings {
            SettingsView()
                .environmentObject(serverManager)
        }
    }
}

/// Decides whether to show onboarding or the main interface based on the
/// detected environment. Placeholder routing for Phase 1.
struct RootView: View {
    @EnvironmentObject private var environmentChecker: EnvironmentChecker

    var body: some View {
        Group {
            if environmentChecker.isReady {
                MainView()
            } else {
                OnboardingView()
            }
        }
    }
}
