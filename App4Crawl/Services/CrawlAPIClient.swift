//
//  CrawlAPIClient.swift
//  App4Crawl
//
//  Async HTTP client for the local FastAPI backend (PROJECTBRIEF §8). Talks to
//  127.0.0.1 only. All requests/responses are JSON; the live stream uses SSE.
//

import Foundation

// MARK: - Shared JSON coders

extension JSONEncoder {
    /// Encoder configured for the server's snake_case wire format.
    static func app(pretty: Bool = false) -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        if pretty {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        }
        return encoder
    }
}

extension JSONDecoder {
    /// Decoder configured for the server's snake_case wire format.
    static func app() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}

// MARK: - Client

/// Talks to the local FastAPI server over `127.0.0.1`.
struct CrawlAPIClient {
    /// Base URL of the running backend, e.g. `http://127.0.0.1:<port>`.
    let baseURL: URL
    private let session: URLSession

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    enum APIError: LocalizedError {
        case http(status: Int, detail: String?)
        case decoding(String)
        case transport(String)

        var errorDescription: String? {
            switch self {
            case .http(let status, let detail):
                return "Server error \(status)\(detail.map { ": \($0)" } ?? "")"
            case .decoding(let message):
                return "Could not read server response: \(message)"
            case .transport(let message):
                return message
            }
        }
    }

    // MARK: Endpoints

    /// `GET /health`
    func health() async throws -> HealthResponseDTO {
        try await get("health")
    }

    /// `GET /providers`
    func providers() async throws -> ProvidersResponseDTO {
        try await get("providers")
    }

    /// `POST /crawl/single`
    func startSingle(_ request: SingleCrawlRequestDTO) async throws -> JobCreatedResponseDTO {
        try await post("crawl/single", body: request)
    }

    /// `POST /crawl/deep`
    func startDeep(_ request: DeepCrawlRequestDTO) async throws -> JobCreatedResponseDTO {
        try await post("crawl/deep", body: request)
    }

    /// `GET /crawl/{job_id}/status`
    func status(jobID: String) async throws -> JobStatusResponseDTO {
        try await get("crawl/\(jobID)/status")
    }

    /// `GET /crawl/{job_id}/result`
    func result(jobID: String) async throws -> JobResultResponseDTO {
        try await get("crawl/\(jobID)/result")
    }

    /// `DELETE /crawl/{job_id}`
    func cancel(jobID: String) async throws {
        var request = URLRequest(url: url(for: "crawl/\(jobID)"))
        request.httpMethod = "DELETE"
        _ = try await send(request)
    }

    /// `GET /crawl/{job_id}/stream` — Server-Sent Events for live progress.
    func events(jobID: String) -> AsyncThrowingStream<SSEMessage, Error> {
        let streamURL = url(for: "crawl/\(jobID)/stream")
        let session = self.session
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: streamURL)
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                        throw APIError.http(
                            status: (response as? HTTPURLResponse)?.statusCode ?? -1,
                            detail: nil)
                    }
                    var event = "message"
                    var data = ""
                    for try await line in bytes.lines {
                        if line.isEmpty {
                            if !data.isEmpty {
                                continuation.yield(SSEMessage(event: event, data: data))
                            }
                            event = "message"
                            data = ""
                        } else if line.hasPrefix("event:") {
                            event = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
                        } else if line.hasPrefix("data:") {
                            data = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: Plumbing

    private func url(for path: String) -> URL {
        baseURL.appendingPathComponent(path)
    }

    private func get<Response: Decodable>(_ path: String) async throws -> Response {
        let request = URLRequest(url: url(for: path))
        let data = try await send(request)
        return try decode(data)
    }

    private func post<Body: Encodable, Response: Decodable>(
        _ path: String, body: Body
    ) async throws -> Response {
        var request = URLRequest(url: url(for: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            request.httpBody = try JSONEncoder.app().encode(body)
        } catch {
            throw APIError.decoding(error.localizedDescription)
        }
        let data = try await send(request)
        return try decode(data)
    }

    /// Send a request, mapping transport and HTTP errors to `APIError`.
    @discardableResult
    private func send(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw APIError.transport("Malformed response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let detail = (try? JSONDecoder.app().decode(ErrorBody.self, from: data))?.detail
            throw APIError.http(status: http.statusCode, detail: detail)
        }
        return data
    }

    private func decode<Response: Decodable>(_ data: Data) throws -> Response {
        do {
            return try JSONDecoder.app().decode(Response.self, from: data)
        } catch {
            throw APIError.decoding(error.localizedDescription)
        }
    }

    private struct ErrorBody: Decodable {
        let detail: String?
    }
}

/// A single Server-Sent Event message.
struct SSEMessage: Equatable {
    let event: String
    let data: String
}
