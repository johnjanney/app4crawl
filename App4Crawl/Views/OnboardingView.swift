//
//  OnboardingView.swift
//  App4Crawl
//
//  First-launch install flow: environment check, install, live progress,
//  verification, and completion. Placeholder for Phase 1; implemented in Phase 3.
//

import SwiftUI

struct OnboardingView: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("Welcome to App4Crawl")
                .font(.largeTitle)
                .bold()
            Text("Setting up your crawling environment…")
                .foregroundStyle(.secondary)
            ProgressView()
        }
        .padding(40)
        .frame(minWidth: 520, minHeight: 360)
    }
}

#Preview {
    OnboardingView()
}
