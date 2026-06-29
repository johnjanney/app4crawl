//
//  App4CrawlApp.swift
//  App4Crawl
//
//  App entry point. Owns the FastAPI server lifecycle and the environment
//  checker, and routes between the onboarding flow and the main UI.
//

import SwiftUI

@main
struct App4CrawlApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @AppStorage(AppDefaults.appearance) private var appearanceRaw = AppTheme.system.rawValue

    private var colorScheme: ColorScheme? {
        AppTheme(rawValue: appearanceRaw)?.colorScheme
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appDelegate.serverManager)
                .environmentObject(appDelegate.environmentChecker)
                .environmentObject(appDelegate.historyStore)
                .preferredColorScheme(colorScheme)
        }
        .windowStyle(.titleBar)
        .commands {
            // Native menu commands (New Crawl, etc.) added in later phases.
        }

        Settings {
            SettingsView()
                .environmentObject(appDelegate.serverManager)
                .environmentObject(appDelegate.environmentChecker)
                .preferredColorScheme(colorScheme)
        }
    }
}

/// Owns long-lived services so the server can be torn down on app termination
/// (PROJECTBRIEF §2: shut the server down cleanly on quit).
final class AppDelegate: NSObject, NSApplicationDelegate {
    let serverManager = ServerManager()
    let environmentChecker = EnvironmentChecker()
    let historyStore = HistoryStore()

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            serverManager.stop()
        }
    }
}

/// Routes between onboarding and the main UI based on the detected environment,
/// and starts the backend once the environment is ready.
struct RootView: View {
    @EnvironmentObject private var environment: EnvironmentChecker
    @EnvironmentObject private var server: ServerManager

    var body: some View {
        Group {
            if environment.isReady {
                MainView()
            } else {
                OnboardingView()
            }
        }
        .task {
            if case .unknown = environment.state {
                await environment.check()
            }
        }
        .onChange(of: environment.state) { _, newState in
            if case .ready(let info) = newState {
                Task { await startServer(with: info) }
            }
        }
    }

    /// Launch the FastAPI backend with the detected interpreter.
    private func startServer(with info: EnvironmentInfo) async {
        guard !server.isRunning,
              let serverDirectory = ServerManager.bundledServerDirectory()
        else { return }
        await server.start(
            pythonURL: URL(fileURLWithPath: info.pythonPath),
            serverDirectory: serverDirectory)
    }
}
