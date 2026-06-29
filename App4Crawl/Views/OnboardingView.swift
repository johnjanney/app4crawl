//
//  OnboardingView.swift
//  App4Crawl
//
//  First-launch install flow (PROJECTBRIEF §4): environment check, install with
//  live progress, verification, and completion. Driven by EnvironmentChecker.
//

import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var environment: EnvironmentChecker

    var body: some View {
        VStack(spacing: 20) {
            header

            Group {
                switch environment.state {
                case .unknown, .checking:
                    checkingView
                case .needsInstall(let pythonVersion):
                    needsInstallView(pythonVersion: pythonVersion)
                case .installing:
                    installingView
                case .pythonMissing(let message):
                    pythonMissingView(message: message)
                case .failed(let message):
                    failedView(message: message)
                case .ready:
                    readyView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(40)
        .frame(minWidth: 620, minHeight: 460)
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 6) {
            Text("Welcome to App4Crawl")
                .font(.largeTitle.bold())
            Text("Let’s set up your crawling environment.")
                .foregroundStyle(.secondary)
        }
    }

    private var checkingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Checking for Python and Crawl4AI…")
                .foregroundStyle(.secondary)
        }
    }

    private func needsInstallView(pythonVersion: String) -> some View {
        VStack(spacing: 16) {
            Label("Python \(pythonVersion) found", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text("Crawl4AI isn’t installed yet. App4Crawl will set up an isolated "
                + "environment and download a managed copy of Chromium.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button {
                Task { await environment.install() }
            } label: {
                Text("Install Crawl4AI").frame(minWidth: 160)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
        }
    }

    private var installingView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ProgressView()
                Text("Installing… this can take a few minutes.")
                    .foregroundStyle(.secondary)
            }
            logView
        }
    }

    private func pythonMissingView(message: String) -> some View {
        VStack(spacing: 16) {
            Label("Python 3.10+ not found", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Link("Download Python", destination: URL(string: "https://www.python.org/downloads/")!)
                .buttonStyle(.borderedProminent)
            Button("Check Again") { Task { await environment.check() } }
        }
    }

    private func failedView(message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Installation failed", systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red)
            Text(message)
                .foregroundStyle(.secondary)
            logView
            Button("Try Again") { Task { await environment.install() } }
                .buttonStyle(.borderedProminent)
        }
    }

    private var readyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.green)
            Text("All set!")
                .font(.title2.bold())
            Text("Starting App4Crawl…")
                .foregroundStyle(.secondary)
        }
    }

    /// Live, auto-scrolling install log (PROJECTBRIEF §4: don't hide behind a
    /// spinner only).
    private var logView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(environment.installLog.enumerated()), id: \.offset) { index, line in
                        Text(line)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(index)
                    }
                }
                .padding(8)
            }
            .frame(minHeight: 200)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))
            .onChange(of: environment.installLog.count) { _, count in
                withAnimation { proxy.scrollTo(count - 1, anchor: .bottom) }
            }
        }
    }
}

#Preview {
    OnboardingView()
        .environmentObject(EnvironmentChecker())
}
