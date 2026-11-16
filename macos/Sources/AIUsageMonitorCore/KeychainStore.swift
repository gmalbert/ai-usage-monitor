/// macOS Keychain storage for the OpenCode Go API key. Mac counterpart of
/// `credential_store.py` (which uses the Windows Credential Manager).
///
/// The key is a generic-password item in the user's login keychain; it is
/// never written to UserDefaults, configuration files, the cache, or logs.
///
/// Prompt-safety rules: reading an item's *data* can trigger a keychain ACL
/// consent dialog when the item was created by a differently signed build —
/// and ad-hoc signatures change on every rebuild. To guarantee that the app
/// and the widget never block on, or surface, a consent dialog:
///
/// - `hasKey` performs a metadata-only query (no data, no prompt).
/// - `loadKey` only reads data after this build's user has linked the key
///   via `saveKey` (a UserDefaults flag), because `saveKey` also writes an
///   any-application-trusted ACL so future reads stay silent.
import Foundation
import Security

public struct KeychainStore: OpenCodeKeyStorage {
    public static let shared = KeychainStore()
    public let service: String
    public let account: String
    private let defaults: UserDefaults

    private static let linkedFlag = "opencodeKeyLinkedToThisStore"

    public init(service: String = "AIUsageMonitor", account: String = "OpenCodeGoApiKey", defaults: UserDefaults = .standard) {
        self.service = service
        self.account = account
        self.defaults = defaults
    }

    public func loadKey() -> String? {
        // Only read data for an item this store created with its
        // any-application ACL. A legacy item from another build would
        // trigger an ACL consent dialog on read; refuse instead.
        guard isLinked else { return nil }
        // Reading requires an unlocked login keychain; on a locked one the
        // call would make securityd display an unlock prompt. Treat a
        // locked keychain as "no key stored".
        guard Self.loginKeychainUnlocked else { return nil }
        var query = Self.baseQuery(service: service, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            if status == errSecItemNotFound {
                clearLinkedFlag()
            }
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    public func saveKey(_ key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw KeychainError(message: "The API key cannot be empty")
        }
        guard Self.loginKeychainUnlocked else {
            throw KeychainError(message: "The login keychain is locked, so the key cannot be stored. Unlock the keychain and try again.")
        }
        deleteKey()
        var add = Self.baseQuery(service: service, account: account)
        add[kSecValueData as String] = Data(trimmed.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        if let access = Self.anyApplicationAccess() {
            add[kSecAttrAccess as String] = access
        }
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError(message: "Keychain write failed (\(status))")
        }
        setLinkedFlag()
    }

    /// True when a key item exists, using a metadata-only query so startup
    /// and Settings can display its state without ever touching item data.
    public var hasKey: Bool {
        var query = Self.baseQuery(service: service, account: account)
        query[kSecReturnAttributes as String] = true
        query[kSecReturnData as String] = false
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        return SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess
    }

    /// True when this store saved the current key, meaning `loadKey` can
    /// read it silently. A key saved by an older build must be re-entered
    /// once to link it.
    public var isLinked: Bool {
        defaults.bool(forKey: Self.linkedFlag)
    }

    @discardableResult
    public func deleteKey() -> Bool {
        let query = Self.baseQuery(service: service, account: account)
        let deleted = SecItemDelete(query as CFDictionary) == errSecSuccess
        if deleted {
            clearLinkedFlag()
        }
        return deleted
    }

    private func setLinkedFlag() {
        defaults.set(true, forKey: Self.linkedFlag)
    }

    private func clearLinkedFlag() {
        defaults.removeObject(forKey: Self.linkedFlag)
    }

    /// True when the user's login keychain is unlocked. Keychain operations
    /// on a locked login keychain would pop a password prompt on the
    /// user's screen; callers refuse instead.
    public static var loginKeychainUnlocked: Bool {
        var keychain: SecKeychain?
        guard SecKeychainCopyDefault(&keychain) == errSecSuccess, let keychain else { return false }
        var status: UInt32 = 0
        guard SecKeychainGetStatus(keychain, &status) == errSecSuccess else { return false }
        return status & 0x0001 != 0  // kSecUnlockStateStatus
    }

    /// An access control that lets any application read the item without a
    /// consent dialog, mirroring the silent reads of the Windows Credential
    /// Manager. Without this, every new code signature (including each
    /// ad-hoc rebuild during development) would re-prompt for access.
    private static func anyApplicationAccess() -> SecAccess? {
        var anyApp: SecTrustedApplication?
        guard SecTrustedApplicationCreateFromPath(nil, &anyApp) == errSecSuccess, let anyApp else {
            return nil
        }
        var access: SecAccess?
        guard SecAccessCreate("AI Usage Monitor" as CFString, [anyApp] as CFArray, &access) == errSecSuccess else {
            return nil
        }
        return access
    }

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
