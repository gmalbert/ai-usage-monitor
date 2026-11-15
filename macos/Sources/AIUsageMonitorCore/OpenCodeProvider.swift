/// OpenCode Go adapter. Port of `providers/opencode.py`.
///
/// Key resolution order: explicit constructor key, `OPENCODEGO_KEY`
/// environment variable, the macOS Keychain entry, then pre-existing OpenCode
/// credential files. Requires all three usage windows in the response.
import Foundation

/// Abstraction over the secure OpenCode Go key storage so tests can use an
/// in-memory implementation; production uses `KeychainStore`.
public protocol OpenCodeKeyStorage: Sendable {
    func loadKey() -> String?
}

public struct OpenCodeGoProvider: UsageProvider {
    public let key = "opencode"
    public var displayName: String { "OpenCode Go" }

    public static let usageURL = URL(string: "https://opencode.ai/zen/go/v1/usage")!

    struct MissingKeyError: Error, CustomStringConvertible {
        let description = "OpenCode Go API key is missing. Add it in Settings or set OPENCODE_GO_API_KEY."
    }

    private let explicitKey: String?
    private let keychain: any OpenCodeKeyStorage
    private let homeDirectory: URL
    private let transport: any ProviderTransport
    private let environment: [String: String]

    public init(
        apiKey: String? = nil,
        keychain: any OpenCodeKeyStorage = KeychainStore.shared,
        homeDirectory: URL? = nil,
        transport: any ProviderTransport = URLSessionTransport(),
        environment: [String: String]? = nil
    ) {
        self.explicitKey = apiKey
        self.keychain = keychain
        self.homeDirectory = homeDirectory ?? FileManager.default.homeDirectoryForCurrentUser
        self.transport = transport
        self.environment = environment ?? ProcessInfo.processInfo.environment
    }

    /// Reads a pre-existing OpenCode credential store when its common JSON
    /// layout is present; mirrors `_stored_api_key()`.
    static func storedAPIKey(in homeDirectory: URL) -> String? {
        let candidates = [
            homeDirectory.appendingPathComponent(".config/opencode/auth.json"),
            homeDirectory.appendingPathComponent(".local/share/opencode/auth.json"),
        ]
        for path in candidates {
            guard let data = try? Data(contentsOf: path),
                  let object = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any] else {
                continue
            }
            for field in ["apiKey", "api_key", "token"] {
                if let value = object[field] as? String, !value.isEmpty {
                    return value
                }
            }
        }
        return nil
    }

    public func fetch() async throws -> ProviderUsage {
        let apiKey = explicitKey
            ?? environment["OPENCODE_GO_API_KEY"]
            ?? keychain.loadKey()
            ?? Self.storedAPIKey(in: homeDirectory)
        guard let apiKey, !apiKey.isEmpty else {
            throw MissingKeyError()
        }
        let payload = try await transport.getJSON(Self.usageURL, token: apiKey, params: nil)
        guard let usage = payload["usage"] as? [String: Any] else {
            throw SchemaError("OpenCode Go usage API format changed. Provider adapter needs updating.")
        }
        return ProviderUsage(
            provider: "OpenCode Go",
            plan: "Go",
            status: .ok,
            fiveHour: try Self.makeWindow(usage, key: "rolling", name: "5-hour"),
            weekly: try Self.makeWindow(usage, key: "weekly", name: "Weekly"),
            monthly: try Self.makeWindow(usage, key: "monthly", name: "Monthly"),
            fetchedAt: Date()
        )
    }

    static func makeWindow(_ usage: [String: Any], key: String, name: String) throws -> UsageWindow {
        guard let value = usage[key] as? [String: Any], value["percent"] != nil, value["resetsAt"] != nil else {
            throw SchemaError("OpenCode Go usage API format changed. Provider adapter needs updating.")
        }
        let resetAt = try localFromISO(value["resetsAt"], "usage.\(key).resetsAt")
        return try windowFromPercent(name, usedPercent: value["percent"], resetAt: resetAt)
    }
}
