import AppKit
import Foundation
import Observation
import WidgetKit
import AIUsageMonitorCore

/// The observable state the menu-bar UI renders, and the single owner of the
/// refresh loop. UI updates happen on the main actor; provider work runs on
/// the `UsageService` actor so refreshes are serialized.
@MainActor
@Observable
final class AppStore {
    enum SettingsTab: Hashable {
        case general, opencode, diagnostics
    }

    private(set) var values: [String: ProviderUsage] = [:]
    private(set) var settings: AppSettings
    private(set) var isRefreshing = false
    private(set) var lastRefreshedAt: Date?
    private(set) var opencodeKeyPresent: Bool
    /// True when the saved key was linked to this store's Keychain item, so
    /// automatic refreshes may read it silently.
    private(set) var opencodeKeyLinked: Bool
    /// The channel the widget reads: "app-group" when provisioned,
    /// "keychain" for entitled development-signed builds, "shared-folder"
    /// for local ad-hoc builds, "none" when nothing is reachable.
    private(set) var snapshotChannel: String = "none"
    /// The Settings tab to show when the window opens.
    private(set) var settingsTab: SettingsTab = .general

    func selectSettingsTab(_ tab: SettingsTab) {
        settingsTab = tab
    }

    private let service: UsageService
    private let keychain: KeychainStore
    private let notifier: Notifier
    private let log: RotatingFileLog
    private var loopTask: Task<Void, Never>?

    init(
        service: UsageService? = nil,
        keychain: KeychainStore = .shared,
        notifier: Notifier = .shared,
        log: RotatingFileLog = .shared
    ) {
        self.settings = SettingsStore.load()
        self.keychain = keychain
        self.notifier = notifier
        self.log = log
        self.opencodeKeyPresent = keychain.hasKey
        self.opencodeKeyLinked = keychain.isLinked
        let providers: [any UsageProvider] = [
            CommandCodeProvider(),
            OpenCodeGoProvider(keychain: keychain),
            CodexProvider(),
        ]
        self.service = service ?? UsageService(providers: providers)
        log.info("Application started")
        Task {
            // Single-instance guard: if a sibling instance is already
            // serving the loopback endpoint, quit instead of stacking a
            // second gauge in the menu bar.
            if await SnapshotServer.isSiblingInstanceRunning() {
                log.warn("Another AI Usage Monitor instance is already running; exiting")
                NSApp.terminate(nil)
                return
            }
            SnapshotServer.shared.start()
            await self.refresh()
        }
        startRefreshLoop()
        observeWake()
    }

    // MARK: - Derived state

    var lowestRemaining: Double? {
        let candidates = values.values
            .filter { $0.status == .ok }
            .flatMap { usage in usage.windows().map { $0.remainingPercent } }
        return candidates.min()
    }

    var gaugeState: String {
        guard let lowest = lowestRemaining else { return "degraded" }
        if lowest < settings.criticalThreshold { return "critical" }
        if lowest < settings.warningThreshold { return "warning" }
        return "normal"
    }

    var orderedProviders: [ProviderUsage] {
        let order = ["commandcode", "opencode", "codex"]
        return values
            .sorted { lhs, rhs in
                let l = order.firstIndex(of: lhs.key) ?? order.count
                let r = order.firstIndex(of: rhs.key) ?? order.count
                return l < r
            }
            .map(\.value)
    }

    var valuesByKey: [String: ProviderUsage] { values }

    /// The menu-bar hover text: every provider with per-window remaining
    /// percentages and reset countdowns. Codex is omitted when its live
    /// refresh did not succeed, mirroring the Windows tray tooltip.
    var hoverText: String {
        var lines: [String] = []
        let updated = lastRefreshedAt.map { "updated \(relativeAge(since: $0))" } ?? "no data yet"
        if let lowest = lowestRemaining {
            lines.append("AI Usage Monitor — lowest \(Int(lowest.rounded()))% remaining · \(updated)")
        } else {
            lines.append("AI Usage Monitor — no live data · \(updated)")
        }
        for usage in orderedProviders {
            if usage.provider == "Codex" && (usage.stale || usage.status != .ok) {
                continue
            }
            if usage.windows().isEmpty {
                lines.append("\(usage.provider): unavailable — \(usage.error ?? usage.status.label)")
                continue
            }
            let label = usage.provider + (usage.plan.map { " — \($0)" } ?? "")
            let parts = usage.windows().map { window -> String in
                var text = "\(shortName(window.name)) \(Int(window.remainingPercent.rounded()))%"
                if let resetAt = window.resetAt {
                    text += " (\(relativeCountdown(to: resetAt)))"
                }
                return text
            }
            lines.append("\(label): " + parts.joined(separator: " · ") + (usage.stale ? " (stale)" : ""))
        }
        return lines.joined(separator: "\n")
    }

    private func shortName(_ windowName: String) -> String {
        switch windowName {
        case "5-hour": return "5h"
        case "Weekly": return "Week"
        case "Monthly": return "Month"
        default: return windowName
        }
    }

    // MARK: - Refresh

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            values = await service.refresh()
            lastRefreshedAt = Date()
            log.info("Refresh finished: \(values.count) provider entries")
        }
        let events = await service.evaluateThresholds(settings: settings)
        if settings.showNotifications, !events.isEmpty {
            await notifier.post(events)
        }
        publishSnapshot()
    }

    private func publishSnapshot() {
        let snapshot = UsageSnapshot.make(from: values, settings: settings)
        // Channel order: App Group container when provisioned, then the
        // shared Keychain item (entitled development-signed builds), then
        // the /Users/Shared file the sandboxed widget reads for local
        // ad-hoc builds.
        SnapshotServer.shared.update(snapshot)
        let channel: String
        do {
            try SnapshotStore.save(snapshot)
            channel = "app-group"
        } catch {
            if SharedSnapshotStore.selfEntitled(), SharedSnapshotStore.save(snapshot) {
                channel = "keychain"
            } else {
                // Without the entitlement the widget could only read the
                // keychain item through an ACL consent prompt; remove any
                // stale item so no prompt can ever appear.
                SharedSnapshotStore.delete()
                channel = SharedFolderSnapshotStore.save(snapshot) ? "shared-folder" : "none"
            }
        }
        if channel != snapshotChannel {
            log.info("Widget snapshot channel: \(channel)")
        }
        snapshotChannel = channel
        for kind in WidgetKinds.allGauges {
            WidgetCenter.shared.reloadTimelines(ofKind: kind)
        }
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKinds.providers)
    }

    // MARK: - Auto refresh

    func startRefreshLoop() {
        loopTask?.cancel()
        let interval = settings.refreshSeconds
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard let self, !Task.isCancelled else { return }
                await self.refresh()
            }
        }
    }

    private func observeWake() {
        NotificationCenter.default.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.log.info("System woke; refreshing")
                await self?.refresh()
            }
        }
    }

    // MARK: - Settings

    func update(settings newSettings: AppSettings) {
        let previousInterval = settings.refreshSeconds
        settings = newSettings
        SettingsStore.save(newSettings)
        if newSettings.showNotifications {
            Task { await notifier.ensureAuthorization() }
        }
        if newSettings.refreshSeconds != previousInterval {
            startRefreshLoop()
        }
    }

    func toggleLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try LoginItemController.register()
            } else {
                try LoginItemController.unregister()
            }
        } catch {
            log.warn("Login item change failed: \(error.localizedDescription)")
        }
    }

    // MARK: - OpenCode Go key management

    func saveOpencodeKey(_ key: String) throws {
        try keychain.saveKey(key)
        opencodeKeyPresent = keychain.hasKey
        opencodeKeyLinked = keychain.isLinked
        log.info("OpenCode Go key saved to Keychain")
        Task { await refresh() }
    }

    func removeOpencodeKey() {
        keychain.deleteKey()
        opencodeKeyPresent = keychain.hasKey
        opencodeKeyLinked = keychain.isLinked
        log.info("OpenCode Go key removed from Keychain")
        Task { await refresh() }
    }
}
