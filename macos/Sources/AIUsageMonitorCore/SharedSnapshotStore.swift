import Foundation
import Security

/// Keychain-backed snapshot channel between the host app and the widget.
///
/// The App Group container and loopback HTTP fetch both require a
/// provisioned build on modern macOS. Keychain access groups are validated
/// by securityd against each binary's `keychain-access-groups` entitlement
/// instead, which works for locally development-signed builds from the
/// same team. The item holds only usage percentages and reset times.
public enum SharedSnapshotStore {
    public static let accessGroup = "com.gmalbert.aiusagemonitor.shared"
    private static let service = "AIUsageMonitorWidgetSnapshot"
    private static let account = "latest"

    /// Saves the latest snapshot, replacing any previous one.
    public static func save(_ snapshot: UsageSnapshot) -> Bool {
        // Keychain writes on a locked login keychain make securityd display
        // an unlock prompt; refuse instead so no prompt can ever appear.
        guard KeychainStore.loginKeychainUnlocked else { return false }
        guard let data = try? JSONEncoder.withISODates().encode(snapshot) else {
            return false
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: accessGroup,
        ]
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = data
        let status = SecItemAdd(attributes as CFDictionary, nil)
        return status == errSecSuccess
    }

    /// Loads the latest snapshot written by the host app, if any.
    public static func load() -> UsageSnapshot? {
        // Reads are refused on a locked login keychain for the same reason
        // as writes: an unauthorized access would prompt for consent.
        guard KeychainStore.loginKeychainUnlocked else { return nil }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: accessGroup,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else {
            return nil
        }
        return try? JSONDecoder.withISODates().decode(UsageSnapshot.self, from: data)
    }

    /// True when this binary is entitled to the shared keychain access
    /// group *and* its signature can actually satisfy that entitlement.
    /// Both the writing app and the reading widget consult this so an
    /// unprovisioned build cannot create or read the item — an unauthorized
    /// read would trigger a keychain ACL consent prompt on every widget
    /// refresh. Ad-hoc builds embed the entitlement but securityd cannot
    /// validate their keychain access group (there is no team identity), so
    /// they count as unentitled.
    public static func selfEntitled() -> Bool {
        guard !Self.adHocSigned, let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(task, "keychain-access-groups" as CFString, nil) else {
            return false
        }
        guard let groups = value as? [String] else { return false }
        return groups.contains(accessGroup)
    }

    /// True when the running binary is only ad-hoc signed.
    private static var adHocSigned: Bool {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return true }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return true }
        var info: CFDictionary?
        // kSecCSSigningInformation (1) is a C macro not exposed to Swift.
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: 1), &info) == errSecSuccess,
              let info else { return true }
        let flags = (info as? [String: Any])?[kSecCodeInfoFlags as String] as? UInt32 ?? 0
        // kSecCodeSignatureAdhoc (0x00020000) is a C macro not exposed to
        // Swift.
        return flags & 0x0002_0000 != 0
    }

    /// Removes the shared snapshot item.
    public static func delete() {
        guard KeychainStore.loginKeychainUnlocked else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: accessGroup,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
