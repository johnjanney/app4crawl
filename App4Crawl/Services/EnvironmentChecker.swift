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

    /// Python script that reports interpreter and Crawl4AI versions in one shot.
    private static let probeScript = """
        import sys
        v = sys.version_info
        print("PY %d.%d.%d" % (v.major, v.minor, v.micro))
        try:
            import crawl4ai
            print("C4AI " + getattr(crawl4ai, "__version__", "unknown"))
        except Exception:
            print("C4AI -")
        """

    // MARK: - Detection

    /// Runs the detection sequence (managed venv → system Python).
    func check() async {
        state = .checking

        // 1. Managed venv.
        if FileManager.default.isExecutableFile(atPath: AppPaths.venvPython.path) {
            let probe = await probe(pythonURL: AppPaths.venvPython, viaEnv: false)
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

        // 2. System Python.
        let systemProbe = await probe(pythonURL: nil, viaEnv: true)
        guard let sysVersion = systemProbe.pythonVersion,
              let tuple = systemProbe.versionTuple,
              meetsMinimum(tuple)
        else {
            state = .pythonMissing(
                message: """
                    Python \(AppPaths.minimumPythonVersion.major).\
                    \(AppPaths.minimumPythonVersion.minor)+ was not found. \
                    Install Python from python.org, or with Homebrew: \
                    brew install python
                    """)
            return
        }

        if let c4ai = systemProbe.crawl4aiVersion {
            let path = await resolveSystemPythonPath() ?? "/usr/bin/env"
            state = .ready(
                EnvironmentInfo(
                    source: .systemPython,
                    pythonPath: path,
                    pythonVersion: sysVersion,
                    crawl4aiVersion: c4ai))
        } else {
            state = .needsInstall(pythonVersion: sysVersion)
        }
    }

    /// Probe an interpreter for its version and Crawl4AI availability.
    private func probe(pythonURL: URL?, viaEnv: Bool) async -> ProbeResult {
        var result = ProbeResult()
        let collector = OutputCollector()
        do {
            let run: ProcessRunResult
            if viaEnv {
                run = try await ProcessRunner.runViaEnv(
                    tool: "python3",
                    arguments: ["-c", Self.probeScript],
                    onOutput: { collector.append($0) })
            } else if let pythonURL {
                run = try await ProcessRunner.run(
                    executableURL: pythonURL,
                    arguments: ["-c", Self.probeScript],
                    onOutput: { collector.append($0) })
            } else {
                return result
            }
            _ = run
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

            try await step("Creating virtual environment…") {
                try await ProcessRunner.runViaEnv(
                    tool: "python3",
                    arguments: ["-m", "venv", AppPaths.venv.path],
                    onOutput: self.appendLog)
            }

            try await step("Upgrading pip…") {
                try await ProcessRunner.run(
                    executableURL: AppPaths.venvPython,
                    arguments: ["-m", "pip", "install", "--upgrade", "pip"],
                    onOutput: self.appendLog)
            }

            try await step("Installing Crawl4AI (this can take a few minutes)…") {
                try await ProcessRunner.run(
                    executableURL: AppPaths.venvPython,
                    arguments: ["-m", "pip", "install", "-U", "crawl4ai"],
                    onOutput: self.appendLog)
            }

            // The bundled FastAPI server runs from this same venv (PROJECTBRIEF
            // §2), so it also needs fastapi + uvicorn. (§4 lists only crawl4ai;
            // see OPENQUESTIONS.)
            try await step("Installing server dependencies…") {
                try await ProcessRunner.run(
                    executableURL: AppPaths.venvPython,
                    arguments: ["-m", "pip", "install", "-U", "fastapi", "uvicorn[standard]"],
                    onOutput: self.appendLog)
            }

            try await step("Installing Playwright + Chromium…") {
                try await ProcessRunner.run(
                    executableURL: AppPaths.crawl4aiSetup,
                    arguments: [],
                    onOutput: self.appendLog)
            }

            // Verification (non-fatal: report but continue to re-check).
            await MainActor.run { self.appendLog("==> Verifying installation (crawl4ai-doctor)…") }
            _ = try? await ProcessRunner.run(
                executableURL: AppPaths.crawl4aiDoctor,
                arguments: [],
                onOutput: self.appendLog)

            await check()
            if case .ready = state {
                appendLog("==> Done.")
            } else if case .checking = state {
                // check() left a non-ready state; surface it.
            } else {
                state = .failed(message: "Installation finished but Crawl4AI could not be verified.")
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

    /// Resolve the absolute path of the system `python3`, for later launches.
    private func resolveSystemPythonPath() async -> String? {
        let collector = OutputCollector()
        _ = try? await ProcessRunner.runViaEnv(
            tool: "which",
            arguments: ["python3"],
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
