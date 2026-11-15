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
    /// group. Both the writing app and the reading widget consult this so an
    /// unprovisioned build cannot create or read the item — an unauthorized
    /// read would trigger a keychain ACL consent prompt on every widget
    /// refresh.
    public static func selfEntitled() -> Bool {
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(task, "keychain-access-groups" as CFString, nil) else {
            return false
        }
        guard let groups = value as? [String] else { return false }
        return groups.contains(accessGroup)
    }

    /// Removes the shared snapshot item.
    public static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: accessGroup,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
