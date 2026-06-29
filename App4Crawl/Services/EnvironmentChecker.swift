//
//  EnvironmentChecker.swift
//  App4Crawl
//
//  Detects and installs the Python + Crawl4AI environment per the brief's
//  detection order: managed venv first, then system Python (PROJECTBRIEF §3),
//  and drives the first-launch install flow (PROJECTBRIEF §4).
//

import Foundation

/// Where a usable Crawl4AI environment was found.
enum EnvironmentSource: String, Equatable {
    case managedVenv
    case systemPython
}

/// Details of a detected, usable environment.
struct EnvironmentInfo: Equatable {
    let source: EnvironmentSource
    /// Absolute path to the Python interpreter to use.
    let pythonPath: String
    /// Detected Python version, e.g. "3.11.5".
    let pythonVersion: String
    /// Detected Crawl4AI version.
    let crawl4aiVersion: String
}

/// High-level environment state that drives onboarding vs. main UI.
enum EnvironmentState: Equatable {
    /// Detection has not run yet.
    case unknown
    /// Detection in progress.
    case checking
    /// A usable Crawl4AI environment is available.
    case ready(EnvironmentInfo)
    /// Python 3.10+ is present but Crawl4AI is not installed.
    case needsInstall(pythonVersion: String)
    /// No suitable Python 3.10+ interpreter was found.
    case pythonMissing(message: String)
    /// Installation is currently running.
    case installing
    /// Detection or installation failed.
    case failed(message: String)
}

/// Result of probing a single interpreter.
private struct ProbeResult {
    var pythonVersion: String?
    var versionTuple: (Int, Int)?
    var crawl4aiVersion: String?
}

/// Detects whether a usable Python + Crawl4AI environment is available and
/// performs the managed-venv installation when needed.
@MainActor
final class EnvironmentChecker: ObservableObject {
    /// Current environment state.
    @Published private(set) var state: EnvironmentState = .unknown

    /// Live install log lines, shown in the onboarding view.
    @Published private(set) var installLog: [String] = []

    /// Convenience flag for routing to the main UI.
    var isReady: Bool {
        if case .ready = state { return true }
        return false
    }

    /// The interpreter to launch the server with, once ready.
    var activePythonURL: URL? {
        if case .ready(let info) = state {
            return URL(fileURLWithPath: info.pythonPath)
        }
        return nil
    }

    /// Absolute path to the system Python discovered during the last check,
    /// used to create the managed venv during install.
    private var systemPythonURL: URL?

    /// Python script that reports interpreter and Crawl4AI versions in one shot.
    /// Uses package metadata rather than importing crawl4ai (which is heavy and
    /// can be slow/noisy); this matches how the server's /health detects it.
    private static let probeScript = """
        import sys
        v = sys.version_info
        print("PY %d.%d.%d" % (v.major, v.minor, v.micro))
        try:
            import importlib.metadata as m
            print("C4AI " + m.version("crawl4ai"))
        except Exception:
            print("C4AI -")
        """

    // MARK: - Detection

    /// Runs the detection sequence (managed venv → system Python).
    func check() async {
        state = .checking

        // 1. Managed venv.
        if FileManager.default.isExecutableFile(atPath: AppPaths.venvPython.path) {
            let probe = await probe(AppPaths.venvPython)
            if let pyVersion = probe.pythonVersion, let c4ai = probe.crawl4aiVersion {
                state = .ready(
                    EnvironmentInfo(
                        source: .managedVenv,
                        pythonPath: AppPaths.venvPython.path,
                        pythonVersion: pyVersion,
                        crawl4aiVersion: c4ai))
                return
            }
        }

        // 2. System Python — search known install locations (a GUI app's PATH
        // does not include /usr/local/bin, /opt/homebrew/bin, or the python.org
        // framework, so we cannot rely on `env python3`).
        guard let (url, systemProbe) = await discoverSystemPython() else {
            state = .pythonMissing(
                message: """
                    Python \(AppPaths.minimumPythonVersion.major).\
                    \(AppPaths.minimumPythonVersion.minor)+ was not found. \
                    Install Python from python.org, or with Homebrew: \
                    brew install python
                    """)
            return
        }
        systemPythonURL = url

        if let c4ai = systemProbe.crawl4aiVersion {
            state = .ready(
                EnvironmentInfo(
                    source: .systemPython,
                    pythonPath: url.path,
                    pythonVersion: systemProbe.pythonVersion ?? "unknown",
                    crawl4aiVersion: c4ai))
        } else {
            state = .needsInstall(pythonVersion: systemProbe.pythonVersion ?? "unknown")
        }
    }

    /// Probe an interpreter for its version and Crawl4AI availability.
    private func probe(_ pythonURL: URL) async -> ProbeResult {
        var result = ProbeResult()
        let collector = OutputCollector()
        do {
            _ = try await ProcessRunner.run(
                executableURL: pythonURL,
                arguments: ["-c", Self.probeScript],
                onOutput: { collector.append($0) })
        } catch {
            return result
        }

        for line in collector.lines {
            if line.hasPrefix("PY ") {
                let version = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                result.pythonVersion = version
                result.versionTuple = parseVersion(version)
            } else if line.hasPrefix("C4AI ") {
                let value = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                result.crawl4aiVersion = value == "-" ? nil : value
            }
        }
        return result
    }

    // MARK: - Installation

    /// Runs the managed-venv install flow (PROJECTBRIEF §4), streaming progress
    /// into `installLog`, then re-checks the environment.
    func install() async {
        state = .installing
        installLog = []

        do {
            try AppPaths.ensureDirectories()

            // Resolve the absolute Python to build the venv with.
            let pythonURL: URL
            if let url = systemPythonURL {
                pythonURL = url
            } else if let discovered = await discoverSystemPython() {
                pythonURL = discovered.0
                systemPythonURL = discovered.0
            } else {
                state = .pythonMissing(
                    message: "Python 3.\(AppPaths.minimumPythonVersion.minor)+ was not found.")
                return
            }

            try await step("Creating virtual environment…") {
                try await ProcessRunner.run(
                    executableURL: pythonURL,
                    arguments: ["-m", "venv", AppPaths.venv.path],
                    onOutput: { [weak self] line in self?.appendLog(line) })
            }

            try await step("Upgrading pip…") {
                try await ProcessRunner.run(
                    executableURL: AppPaths.venvPython,
                    arguments: ["-m", "pip", "install", "--upgrade", "pip"],
                    onOutput: { [weak self] line in self?.appendLog(line) })
            }

            try await step("Installing Crawl4AI (this can take a few minutes)…") {
                try await ProcessRunner.run(
                    executableURL: AppPaths.venvPython,
                    arguments: ["-m", "pip", "install", "-U", "crawl4ai"],
                    onOutput: { [weak self] line in self?.appendLog(line) })
            }

            // The bundled FastAPI server runs from this same venv (PROJECTBRIEF
            // §2), so it also needs fastapi + uvicorn. (§4 lists only crawl4ai;
            // see OPENQUESTIONS.)
            try await step("Installing server dependencies…") {
                try await ProcessRunner.run(
                    executableURL: AppPaths.venvPython,
                    arguments: ["-m", "pip", "install", "-U", "fastapi", "uvicorn[standard]"],
                    onOutput: { [weak self] line in self?.appendLog(line) })
            }

            try await step("Installing Playwright + Chromium…") {
                try await ProcessRunner.run(
                    executableURL: AppPaths.crawl4aiSetup,
                    arguments: [],
                    onOutput: { [weak self] line in self?.appendLog(line) })
            }

            // Verification with crawl4ai-doctor (its exit code is authoritative).
            appendLog("==> Verifying installation (crawl4ai-doctor)…")
            let doctor = try? await ProcessRunner.run(
                executableURL: AppPaths.crawl4aiDoctor,
                arguments: [],
                onOutput: { [weak self] line in self?.appendLog(line) })

            // Confirm via metadata as well; either signal is sufficient.
            let probe = await probe(AppPaths.venvPython)
            let doctorPassed = doctor?.didSucceed == true
            if probe.crawl4aiVersion != nil || doctorPassed {
                state = .ready(
                    EnvironmentInfo(
                        source: .managedVenv,
                        pythonPath: AppPaths.venvPython.path,
                        pythonVersion: probe.pythonVersion ?? "unknown",
                        crawl4aiVersion: probe.crawl4aiVersion ?? "installed"))
                appendLog("==> Done.")
            } else {
                state = .failed(
                    message: "Installation finished but Crawl4AI could not be verified.")
            }
        } catch {
            state = .failed(message: error.localizedDescription)
            appendLog("ERROR: \(error.localizedDescription)")
        }
    }

    /// Run one install step, throwing if the command exits non-zero.
    private func step(
        _ message: String,
        _ body: () async throws -> ProcessRunResult
    ) async throws {
        appendLog("==> \(message)")
        let result = try await body()
        if !result.didSucceed {
            throw InstallError.stepFailed(message: message, exitCode: result.exitCode)
        }
    }

    /// Append a line to the install log. `nonisolated` so it can be used as a
    /// `@Sendable` output callback from a background queue; it hops to the main
    /// actor to mutate published state.
    private nonisolated func appendLog(_ line: String) {
        Task { @MainActor in self.installLog.append(line) }
    }

    enum InstallError: LocalizedError {
        case stepFailed(message: String, exitCode: Int32)

        var errorDescription: String? {
            switch self {
            case .stepFailed(let message, let code):
                return "\(message) failed (exit code \(code))."
            }
        }
    }

    // MARK: - Helpers

    private func meetsMinimum(_ tuple: (Int, Int)) -> Bool {
        tuple >= (AppPaths.minimumPythonVersion.major, AppPaths.minimumPythonVersion.minor)
    }

    private func parseVersion(_ version: String) -> (Int, Int)? {
        let parts = version.split(separator: ".").compactMap { Int($0) }
        guard parts.count >= 2 else { return nil }
        return (parts[0], parts[1])
    }

    /// Find the newest usable system Python (≥ minimum) by checking known
    /// install locations and the user's login-shell PATH. Returns the
    /// interpreter URL and its probe result, or `nil` if none qualifies.
    private func discoverSystemPython() async -> (URL, ProbeResult)? {
        var seen = Set<String>()
        var candidates: [URL] = []
        func add(_ path: String) {
            guard !seen.contains(path),
                  FileManager.default.isExecutableFile(atPath: path) else { return }
            seen.insert(path)
            candidates.append(URL(fileURLWithPath: path))
        }

        // python.org framework installs (newest version first).
        let frameworkBase = "/Library/Frameworks/Python.framework/Versions"
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: frameworkBase) {
            for version in versions.sorted(by: >) {
                add("\(frameworkBase)/\(version)/bin/python3")
            }
        }
        // Homebrew (Apple Silicon, then Intel) and system locations.
        add("/opt/homebrew/bin/python3")
        add("/usr/local/bin/python3")
        // Whatever the user's interactive shell resolves (catches pyenv, etc.).
        if let shellPython = await pythonViaLoginShell() {
            add(shellPython)
        }
        add("/usr/bin/python3")

        for url in candidates {
            let probe = await probe(url)
            if let tuple = probe.versionTuple, meetsMinimum(tuple) {
                return (url, probe)
            }
        }
        return nil
    }

    /// Resolve `python3` via the user's login shell, which loads their full PATH.
    private func pythonViaLoginShell() async -> String? {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        guard FileManager.default.isExecutableFile(atPath: shell) else { return nil }
        let collector = OutputCollector()
        _ = try? await ProcessRunner.run(
            executableURL: URL(fileURLWithPath: shell),
            arguments: ["-lc", "command -v python3"],
            onOutput: { collector.append($0) })
        let resolved = collector.lines.first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (resolved?.isEmpty == false) ? resolved : nil
    }
}

/// Thread-safe collector for process output lines.
private final class OutputCollector: @unchecked Sendable {
    private var storage: [String] = []
    private let lock = NSLock()

    func append(_ line: String) {
        lock.lock()
        storage.append(line)
        lock.unlock()
    }

    var lines: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
