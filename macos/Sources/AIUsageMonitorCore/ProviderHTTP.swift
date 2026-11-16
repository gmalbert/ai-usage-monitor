/// Sanitized HTTP wrapper. Mirrors `providers/http.py`: a ten-second timeout,
/// the required `AIUsageMonitor/1.0` user agent (CommandCode rejects default
/// urllib-style identifiers with HTTP 403), and errors that never include
/// response bodies or credentials.
import Foundation

public struct ProviderHTTPError: Error, CustomStringConvertible, Sendable {
    public let statusCode: Int
    public let message: String

    public init(statusCode: Int, message: String? = nil) {
        self.statusCode = statusCode
        self.message = message ?? "HTTP \(statusCode)"
    }

    public var description: String { message }
}

public struct NetworkRequestError: Error, CustomStringConvertible, Sendable {
    public let message: String
    public init(_ message: String = "Network request failed") { self.message = message }
    public var description: String { message }
}

public struct InvalidJSONError: Error, CustomStringConvertible, Sendable {
    public let message: String
    public init(_ message: String = "Provider returned invalid JSON") { self.message = message }
    public var description: String { message }
}

/// Injectable so provider adapters can be tested against fixture payloads.
public protocol ProviderTransport: Sendable {
    func getJSON(_ url: URL, token: String, params: [String: String?]?) async throws -> [String: Any]
}

public struct URLSessionTransport: ProviderTransport {
    public static let userAgent = "AIUsageMonitor/1.0"
    public let timeoutSeconds: TimeInterval

    public init(timeoutSeconds: TimeInterval = 10) {
        self.timeoutSeconds = timeoutSeconds
    }

    public func getJSON(_ url: URL, token: String, params: [String: String?]? = nil) async throws -> [String: Any] {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if let params, !params.isEmpty {
            let queryItems = params
                .filter { $0.value != nil }
                .sorted { $0.key < $1.key }
                .map { URLQueryItem(name: $0.key, value: $0.value) }
            let existing = components?.queryItems ?? []
            components?.queryItems = existing + queryItems
        }
        guard let requestURL = components?.url else {
            throw NetworkRequestError()
        }
        var request = URLRequest(url: requestURL, timeoutInterval: timeoutSeconds)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await withTimeout(seconds: timeoutSeconds + 2) {
                try await URLSession.shared.data(for: request)
            }
        } catch is TimeoutError {
            throw NetworkRequestError("Timed out")
        } catch is CancellationError {
            throw NetworkRequestError("Cancelled")
        } catch {
            throw NetworkRequestError()
        }
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw ProviderHTTPError(statusCode: http.statusCode)
        }
        return try Self.decodeObject(data)
    }

    static func decodeObject(_ data: Data) throws -> [String: Any] {
        let value: Any
        do {
            value = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            throw InvalidJSONError()
        }
        guard let object = value as? [String: Any] else {
            throw InvalidJSONError("Provider returned an unexpected JSON value")
        }
        return object
    }
}

struct TimeoutError: Error {}

/// Runs an async operation with a wall-clock deadline, throwing `TimeoutError`.
/// Deliberately unconstrained (Swift 5 mode): provider payloads are dynamic
/// JSON and are never shared across tasks.
func withTimeout<T>(seconds: TimeInterval, _ operation: @escaping () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw TimeoutError()
        }
        guard let result = try await group.next() else {
            throw TimeoutError()
        }
        group.cancelAll()
        return result
    }
}

// MARK: - Typed accessors over dynamic JSON

public enum JSONField {
    public static func object(_ value: Any?, _ field: String) throws -> [String: Any] {
        if let object = value as? [String: Any] { return object }
        throw SchemaError("\(field) must be an object")
    }

    public static func string(_ value: Any?, _ field: String) throws -> String {
        if let string = value as? String { return string }
        throw SchemaError("\(field) must be a string")
    }
}
