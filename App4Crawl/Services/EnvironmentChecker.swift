//
//  EnvironmentChecker.swift
//  App4Crawl
//
//  Detects Python and Crawl4AI per the brief's detection order: managed venv
//  first, then system Python. Placeholder for Phase 1; implemented in Phase 3.
//

import Foundation

/// Detects whether a usable Python + Crawl4AI environment is available.
@MainActor
final class EnvironmentChecker: ObservableObject {
    /// True when a usable Crawl4AI environment has been detected.
    @Published private(set) var isReady = false

    /// The detected Crawl4AI version, if any.
    @Published private(set) var crawl4aiVersion: String?

    /// Runs the detection sequence (managed venv → system Python).
    /// Implemented in Phase 3.
    func check() {}
}
