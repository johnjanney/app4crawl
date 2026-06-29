//
//  SettingsView.swift
//  App4Crawl
//
//  Preferences (⌘,): API Keys (Keychain-backed), Environment, and Appearance
//  (PROJECTBRIEF §6).
//

import SwiftUI

/// App appearance options.
enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    /// The SwiftUI color scheme, or `nil` to follow the system.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

struct SettingsView: View {
    var body: some View {
        TabView {
            APIKeysSettingsView()
                .tabItem { Label("API Keys", systemImage: "key") }
            EnvironmentSettingsView()
                .tabItem { Label("Environment", systemImage: "gearshape") }
            AppearanceSettingsView()
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
        }
        .frame(width: 520, height: 420)
    }
}

// MARK: - API Keys

struct APIKeysSettingsView: View {
    /// Providers that need a key (Ollama is local and excluded).
    private let providers = LLMProvider.allCases.filter { $0.requiresAPIKey }

    var body: some View {
        Form {
            Section {
                Text("Keys are stored in your macOS Keychain and never written to disk.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(providers) { provider in
                Section(provider.displayName) {
                    APIKeyRow(provider: provider)
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// A single provider's key entry: enter, save, or remove.
private struct APIKeyRow: View {
    let provider: LLMProvider
    private let keychain = KeychainService()

    @State private var value = ""
    @State private var isStored = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SecureField(isStored ? "••••••••  (saved)" : "API key", text: $value)
                    .textFieldStyle(.roundedBorder)
                Button("Save", action: save)
                    .disabled(value.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Remove", role: .destructive, action: remove)
                    .disabled(!isStored)
            }
            if isStored {
                Label("Key saved", systemImage: "checkmark.seal")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .onAppear { isStored = keychain.hasKey(for: provider) }
    }

    private func save() {
        do {
            try keychain.set(value.trimmingCharacters(in: .whitespaces), for: provider)
            value = ""
            isStored = true
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func remove() {
        do {
            try keychain.delete(for: provider)
            value = ""
            isStored = false
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Environment

struct EnvironmentSettingsView: View {
    @EnvironmentObject private var environment: EnvironmentChecker

    var body: some View {
        Form {
            Section("Active environment") {
                statusContent
            }
            Section {
                Button("Check Again") { Task { await environment.check() } }
                Button("Reinstall / Update Crawl4AI") { Task { await environment.install() } }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var statusContent: some View {
        switch environment.state {
        case .ready(let info):
            LabeledContent("Source",
                           value: info.source == .managedVenv ? "Managed environment" : "System Python")
            LabeledContent("Python", value: info.pythonVersion)
            LabeledContent("Crawl4AI", value: info.crawl4aiVersion)
        case .needsInstall(let pythonVersion):
            LabeledContent("Python", value: pythonVersion)
            Text("Crawl4AI is not installed yet.").foregroundStyle(.secondary)
        case .pythonMissing(let message):
            Text(message).foregroundStyle(.secondary)
        case .installing:
            Label("Installing…", systemImage: "arrow.down.circle")
        case .failed(let message):
            Text(message).foregroundStyle(.red)
        case .checking, .unknown:
            Label("Checking…", systemImage: "hourglass")
        }
    }
}

// MARK: - Appearance

struct AppearanceSettingsView: View {
    @AppStorage(AppDefaults.appearance) private var appearanceRaw = AppTheme.system.rawValue

    var body: some View {
        Form {
            Picker("Appearance", selection: $appearanceRaw) {
                ForEach(AppTheme.allCases) { theme in
                    Text(theme.label).tag(theme.rawValue)
                }
            }
            .pickerStyle(.inline)
        }
        .formStyle(.grouped)
    }
}

#Preview {
    SettingsView()
        .environmentObject(EnvironmentChecker())
}
