//
//  ServerManager.swift
//  App4Crawl
//
//  Manages the FastAPI backend subprocess: allocate a dynamic loopback port,
//  launch uvicorn, poll for health, and terminate cleanly on quit
//  (PROJECTBRIEF §2, §8).
//

import Darwin
import Foundation

/// Owns the lifecycle of the bundled FastAPI server subprocess.
@MainActor
final class ServerManager: ObservableObject {
    /// The local port the server is bound to, once running.
    @Published private(set) var port: Int?

    /// Whether the server process is running and has passed a health check.
    @Published private(set) var isRunning = false

    /// The most recent error message, if a start attempt failed.
    @Published private(set) var lastError: String?

    private var process: Process?

    /// Base URL of the running backend, e.g. `http://127.0.0.1:<port>`.
    var baseURL: URL? {
        guard let port else { return nil }
        return URL(string: "http://127.0.0.1:\(port)")
    }

    enum ServerError: LocalizedError {
        case portAllocationFailed
        case serverDirectoryMissing
        case unhealthy

        var errorDescription: String? {
            switch self {
            case .portAllocationFailed: return "Could not allocate a local port."
            case .serverDirectoryMissing: return "Bundled server code was not found."
            case .unhealthy: return "The server did not become healthy in time."
            }
        }
    }

    // MARK: - Lifecycle

    /// Launches the server subprocess using `pythonURL`, serving the FastAPI app
    /// located in `serverDirectory`, then waits until it is healthy.
    func start(pythonURL: URL, serverDirectory: URL) async {
        guard !isRunning, process == nil else { return }
        lastError = nil

        do {
            guard FileManager.default.fileExists(atPath: serverDirectory.path) else {
                throw ServerError.serverDirectoryMissing
            }
            let chosenPort = try Self.allocatePort()
            try AppPaths.ensureDirectories()

            let proc = Process()
            proc.executableURL = pythonURL
            proc.arguments = [
                "-m", "uvicorn", "main:app",
                "--host", "127.0.0.1",
                "--port", "\(chosenPort)",
                "--log-level", "info",
            ]
            proc.currentDirectoryURL = serverDirectory

            var env = ProcessInfo.processInfo.environment
            env["APP4CRAWL_PORT"] = "\(chosenPort)"
            proc.environment = env

            proc.standardOutput = try logHandle()
            proc.standardError = try logHandle()

            proc.terminationHandler = { [weak self] _ in
                Task { @MainActor in
                    self?.isRunning = false
                    self?.port = nil
                    self?.process = nil
                }
            }

            try proc.run()
            process = proc
            port = chosenPort

            guard let baseURL, await waitForHealth(baseURL: baseURL, timeout: 30) else {
                throw ServerError.unhealthy
            }
            isRunning = true
        } catch {
            lastError = error.localizedDescription
            stop()
        }
    }

    /// Terminates the server subprocess cleanly (SIGTERM).
    func stop() {
        if let proc = process, proc.isRunning {
            proc.terminate()
        }
        process = nil
        isRunning = false
        port = nil
    }

    /// Locates the FastAPI server code bundled inside the app.
    static func bundledServerDirectory() -> URL? {
        Bundle.main.url(forResource: "server", withExtension: nil)
    }

    // MARK: - Helpers

    /// Open the server log file for appending.
    private func logHandle() throws -> FileHandle {
        let fm = FileManager.default
        if !fm.fileExists(atPath: AppPaths.serverLog.path) {
            fm.createFile(atPath: AppPaths.serverLog.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: AppPaths.serverLog)
        handle.seekToEndOfFile()
        return handle
    }

    /// Ask the OS for an unused TCP port on the loopback interface.
    nonisolated static func allocatePort() throws -> Int {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ServerError.portAllocationFailed }
        defer { close(fd) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        addr.sin_port = 0  // 0 => OS chooses a free port

        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else { throw ServerError.portAllocationFailed }

        var bound = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &bound) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(fd, $0, &len)
            }
        }
        guard nameResult == 0 else { throw ServerError.portAllocationFailed }
        return Int(UInt16(bigEndian: bound.sin_port))
    }

    /// Poll `GET /health` until it returns 200 or the timeout elapses.
    private func waitForHealth(baseURL: URL, timeout: TimeInterval) async -> Bool {
        let healthURL = baseURL.appendingPathComponent("health")
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            var request = URLRequest(url: healthURL)
            request.timeoutInterval = 2
            if let (_, response) = try? await URLSession.shared.data(for: request),
               let http = response as? HTTPURLResponse,
               http.statusCode == 200 {
                return true
            }
            try? await Task.sleep(nanoseconds: 300_000_000)  // 0.3s
        }
        return false
    }
}
