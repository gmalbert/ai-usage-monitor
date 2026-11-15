import Foundation
import UserNotifications
import AIUsageMonitorCore

/// Threshold-crossing notifications. The delegate is set so alerts appear
/// even while the menu-bar popover is open.
final class Notifier: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = Notifier()

    private let center = UNUserNotificationCenter.current()

    private override init() {
        super.init()
        center.delegate = self
    }

    @MainActor
    func ensureAuthorization() async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    @MainActor
    func post(_ events: [ThresholdEvent]) async {
        guard !events.isEmpty else { return }
        for event in events {
            let content = UNMutableNotificationContent()
            content.title = "AI Usage Monitor"
            content.body = "\(event.providerName) \(event.windowName) has \(Int(event.remainingPercent.rounded()))% remaining."
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: "threshold-\(event.providerName)-\(event.windowName)-\(event.level.rawValue)-\(UUID().uuidString)",
                content: content,
                trigger: nil
            )
            try? await center.add(request)
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
