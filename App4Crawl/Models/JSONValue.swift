//
//  JSONValue.swift
//  App4Crawl
//
//  A Codable representation of arbitrary JSON, used for fields the server types
//  as `Any` (extracted content, extraction schemas) and to drive the JSON tree
//  in the result viewer.
//

import Foundation

/// An arbitrary JSON value.
indirect enum JSONValue: Codable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

extension JSONValue {
    /// A compact, human-readable scalar description (for tree leaf rows).
    var scalarDescription: String {
        switch self {
        case .null: return "null"
        case .bool(let value): return value ? "true" : "false"
        case .number(let value):
            // Render integers without a trailing ".0".
            if value.rounded() == value, abs(value) < 1e15 {
                return String(Int(value))
            }
            return String(value)
        case .string(let value): return value
        case .array(let value): return "[\(value.count)]"
        case .object(let value): return "{\(value.count)}"
        }
    }

    /// Whether this value has children (array/object).
    var isContainer: Bool {
        switch self {
        case .array, .object: return true
        default: return false
        }
    }

    /// Pretty-printed JSON string for the raw JSON display / export.
    func prettyPrinted() -> String {
        guard
            let data = try? JSONEncoder.app(pretty: true).encode(self),
            let string = String(data: data, encoding: .utf8)
        else {
            return scalarDescription
        }
        return string
    }
}
