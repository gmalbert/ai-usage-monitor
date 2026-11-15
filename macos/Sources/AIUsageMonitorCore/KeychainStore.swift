/// macOS Keychain storage for the OpenCode Go API key. Mac counterpart of
/// `credential_store.py` (which uses the Windows Credential Manager).
///
/// The key is a generic-password item in the user's login keychain; it is
/// never written to UserDefaults UserDefaults, configuration files, the
/// cache, or logs.
import Foundation
import Security

public struct KeychainStore: OpenCodeKeyStorage {
    public static let shared = KeychainStore()
    public let service: String
    public let account: String

    public init(service: String = "AIUsageMonitor", account: String = "OpenCodeGoApiKey") {
        self.service = service
        self.account = account
    }

    public func loadKey() -> String? {
        var query = Self.baseQuery(service: service, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    public func saveKey(_ key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw KeychainError(message: "The API key cannot be empty")
        }
        deleteKey()
        var add = Self.baseQuery(service: service, account: account)
        add[kSecValueData as String] = Data(trimmed.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError(message: "Keychain write failed (\(status))")
        }
    }

    @discardableResult
    public func deleteKey() -> Bool {
        let query = Self.baseQuery(service: service, account: account)
        return SecItemDelete(query as CFDictionary) == errSecSuccess
    }

    public var hasKey: Bool { loadKey() != nil }

    private static func baseQuery(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

public struct KeychainError: Error, CustomStringConvertible, Sendable {
    public let message: String
    public init(message: String) { self.message = message }
    public var description: String { message }
}
