//
//  ProcessRunner.swift
//  App4Crawl
//
//  Async helper for running external processes while streaming combined
//  stdout/stderr line by line. Used by EnvironmentChecker for the install flow.
//  ServerManager manages its long-lived subprocess directly (it must not await
//  termination).
//

import Foundation

/// Outcome of a finished process.
struct ProcessRunResult: Sendable {
    /// The process exit status.
    let exitCode: Int32

    /// Whether the process exited successfully (status 0).
    var didSucceed: Bool { exitCode == 0 }
}

/// Thread-safe accumulator that splits incoming bytes into UTF-8 lines.
private final class LineBuffer: @unchecked Sendable {
    private var data = Data()
    private let lock = NSLock()
    private let onLine: @Sendable (String) -> Void

    init(onLine: @escaping @Sendable (String) -> Void) {
        self.onLine = onLine
    }

    /// Append bytes and emit any newly completed lines.
    func append(_ chunk: Data) {
        lock.lock()
        defer { lock.unlock() }
        data.append(chunk)
        while let newline = data.firstIndex(of: 0x0A) {
            let lineData = data.subdata(in: data.startIndex..<newline)
            data.removeSubrange(data.startIndex...newline)
            emit(lineData)
        }
    }

    /// Emit any trailing bytes that were not terminated by a newline.
    func flush() {
        lock.lock()
        defer { lock.unlock() }
        guard !data.isEmpty else { return }
        emit(data)
        data.removeAll()
    }

    private func emit(_ lineData: Data) {
        if let line = String(data: lineData, encoding: .utf8) {
            onLine(line)
        }
    }
}

/// Runs external processes asynchronously.
enum ProcessRunner {
    /// Errors thrown while launching a process.
    enum RunError: LocalizedError {
        case launchFailed(String)

        var errorDescription: String? {
            switch self {
            case .launchFailed(let message):
                return "Failed to launch process: \(message)"
            }
        }
    }

    /// Runs `executableURL` with `arguments`, invoking `onOutput` for each line
    /// of combined stdout/stderr as it is produced, and returns the result.
    ///
    /// - Note: `onOutput` may be called on a background queue; UI callers must
    ///   hop to the main actor before touching published state.
    @discardableResult
    static func run(
        executableURL: URL,
        arguments: [String],
        environment: [String: String]? = nil,
        currentDirectory: URL? = nil,
        onOutput: @escaping @Sendable (String) -> Void
    ) async throws -> ProcessRunResult {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        if let environment { process.environment = environment }
        if let currentDirectory { process.currentDirectoryURL = currentDirectory }

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        let buffer = LineBuffer(onLine: onOutput)
        let readHandle = pipe.fileHandleForReading
        readHandle.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty { return }
            buffer.append(chunk)
        }

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { proc in
                readHandle.readabilityHandler = nil
                buffer.flush()
                continuation.resume(
                    returning: ProcessRunResult(exitCode: proc.terminationStatus))
            }
            do {
                try process.run()
            } catch {
                readHandle.readabilityHandler = nil
                continuation.resume(throwing: RunError.launchFailed(error.localizedDescription))
            }
        }
    }

    /// Convenience: run `/usr/bin/env <tool> <args...>` so PATH is respected.
    @discardableResult
    static func runViaEnv(
        tool: String,
        arguments: [String],
        environment: [String: String]? = nil,
        currentDirectory: URL? = nil,
        onOutput: @escaping @Sendable (String) -> Void
    ) async throws -> ProcessRunResult {
        try await run(
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: [tool] + arguments,
            environment: environment,
            currentDirectory: currentDirectory,
            onOutput: onOutput
        )
    }
}
