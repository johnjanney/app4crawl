//
//  AppPaths.swift
//  App4Crawl
//
//  Central, non-hardcoded path constants for the App4Crawl managed environment
//  (PROJECTBRIEF §3, §13). Everything lives under ~/.app4crawl.
//

import Foundation

/// Filesystem locations for the App4Crawl managed environment.
enum AppPaths {
    /// Root of the managed environment: `~/.app4crawl`.
    static let home: URL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent(".app4crawl", isDirectory: true)

    /// Isolated Python virtual environment: `~/.app4crawl/venv`.
    static let venv: URL = home.appendingPathComponent("venv", isDirectory: true)

    /// Interpreter inside the managed venv.
    static let venvPython: URL = venv.appendingPathComponent("bin/python")

    /// `crawl4ai-setup` entry point inside the managed venv.
    static let crawl4aiSetup: URL = venv.appendingPathComponent("bin/crawl4ai-setup")

    /// `crawl4ai-doctor` entry point inside the managed venv.
    static let crawl4aiDoctor: URL = venv.appendingPathComponent("bin/crawl4ai-doctor")

    /// Non-sensitive app settings directory.
    static let configDir: URL = home.appendingPathComponent("config", isDirectory: true)

    /// Server and crawl logs directory.
    static let logsDir: URL = home.appendingPathComponent("logs", isDirectory: true)

    /// Rotating server log file written by the FastAPI backend.
    static let serverLog: URL = logsDir.appendingPathComponent("server.log")

    /// Minimum supported Python version (PROJECTBRIEF §3).
    static let minimumPythonVersion: (major: Int, minor: Int) = (3, 10)

    /// Creates the managed config and log directories if needed.
    static func ensureDirectories() throws {
        try FileManager.default.createDirectory(
            at: configDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: logsDir, withIntermediateDirectories: true)
    }
}
