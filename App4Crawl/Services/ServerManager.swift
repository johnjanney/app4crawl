//
//  ServerManager.swift
//  App4Crawl
//
//  Manages the FastAPI backend subprocess: launch on a dynamic local port,
//  monitor health, and terminate cleanly on quit. Placeholder for Phase 1;
//  implemented in Phase 3.
//

import Foundation

/// Owns the lifecycle of the bundled FastAPI server subprocess.
@MainActor
final class ServerManager: ObservableObject {
    /// The local port the server is bound to, once running.
    @Published private(set) var port: Int?

    /// Whether the server process is currently running and healthy.
    @Published private(set) var isRunning = false

    /// Launches the server subprocess. Implemented in Phase 3.
    func start() {}

    /// Terminates the server subprocess cleanly. Implemented in Phase 3.
    func stop() {}
}
