/// Non-secret application settings. Mac counterpart of `config.py`.
///
/// Stored in `UserDefaults`; API keys are never kept here — the OpenCode Go
/// key lives in the Keychain.
import Foundation

public struct AppSettings: Codable, Equatable, Sendable {
    public var refreshSeconds: Int
    public var warningThreshold: Double
    public var criticalThreshold: Double
    public var showNotifications: Bool

    public init(
        refreshSeconds: Int = 300,
        warningThreshold: Double = 50,
        criticalThreshold: Double = 20,
        showNotifications: Bool = true
    ) {
        self.refreshSeconds = refreshSeconds
        self.warningThreshold = warningThreshold
        self.criticalThreshold = criticalThreshold
        self.showNotifications = showNotifications
    }

    public enum CodingKeys: String, CodingKey {
        case refreshSeconds = "refresh_seconds"
        case warningThreshold = "warning_threshold"
        case criticalThreshold = "critical_threshold"
        case showNotifications = "show_notifications"
    }
}

public enum SettingsStore {
    public static func load(from defaults: UserDefaults = .standard) -> AppSettings {
        guard let data = defaults.data(forKey: "settings") else {
            return AppSettings()
        }
        return (try? JSONDecoder().decode(AppSettings.self, from: data)) ?? AppSettings()
    }

    public static func save(_ settings: AppSettings, to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: "settings")
    }
}
