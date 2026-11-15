/// The snapshot the menu-bar app publishes for the widget extension.
///
/// Written to the shared App Group container after every refresh and read by
/// the widget's timeline provider. Contains no credentials — only normalized
/// usage values.
import Foundation

public struct SnapshotWindow: Codable, Equatable, Sendable {
    public var name: String
    public var usedPercent: Double
    public var remainingPercent: Double
    public var resetAt: Date?

    public init(name: String, usedPercent: Double, remainingPercent: Double, resetAt: Date?) {
        self.name = name
        self.usedPercent = usedPercent
        self.remainingPercent = remainingPercent
        self.resetAt = resetAt
    }
}

public struct SnapshotProvider: Codable, Equatable, Sendable {
    public var key: String
    public var name: String
    public var plan: String?
    public var stale: Bool
    public var statusMessage: String?
    public var windows: [SnapshotWindow]
    public var creditBalance: Double?
    public var resetCreditsAvailable: Int?

    public init(
        key: String,
        name: String,
        plan: String?,
        stale: Bool,
        statusMessage: String?,
        windows: [SnapshotWindow],
        creditBalance: Double?,
        resetCreditsAvailable: Int?
    ) {
        self.key = key
        self.name = name
        self.plan = plan
        self.stale = stale
        self.statusMessage = statusMessage
        self.windows = windows
        self.creditBalance = creditBalance
        self.resetCreditsAvailable = resetCreditsAvailable
    }
}

public struct UsageSnapshot: Codable, Equatable, Sendable {
    public static let schemaVersion = 1

    public var schemaVersion: Int
    public var savedAt: Date
    public var refreshSeconds: Int
    /// "normal", "warning", "critical", or "degraded".
    public var gaugeState: String
    public var lowestRemainingPercent: Double?
    public var providers: [SnapshotProvider]

    public init(
        schemaVersion: Int = UsageSnapshot.schemaVersion,
        savedAt: Date,
        refreshSeconds: Int,
        gaugeState: String,
        lowestRemainingPercent: Double?,
        providers: [SnapshotProvider]
    ) {
        self.schemaVersion = schemaVersion
        self.savedAt = savedAt
        self.refreshSeconds = refreshSeconds
        self.gaugeState = gaugeState
        self.lowestRemainingPercent = lowestRemainingPercent
        self.providers = providers
    }

    /// Builds the widget view of a refresh result.
    public static func make(
        from values: [String: ProviderUsage],
        settings: AppSettings,
        savedAt: Date = Date()
    ) -> UsageSnapshot {
        let providers = values
            .sorted { $0.key < $1.key }
            .map { (key, usage) -> SnapshotProvider in
                SnapshotProvider(
                    key: key,
                    name: usage.provider,
                    plan: usage.plan,
                    stale: usage.stale || usage.status != .ok,
                    statusMessage: usage.error ?? usage.status.label,
                    windows: usage.windows().map { window in
                        SnapshotWindow(
                            name: window.name,
                            usedPercent: window.usedPercent,
                            remainingPercent: window.remainingPercent,
                            resetAt: window.resetAt
                        )
                    },
                    creditBalance: usage.creditBalance,
                    resetCreditsAvailable: usage.resetCreditsAvailable
                )
            }
        let lowest = Self.lowestRemaining(in: values)
        return UsageSnapshot(
            savedAt: savedAt,
            refreshSeconds: settings.refreshSeconds,
            gaugeState: Self.gaugeState(lowest: lowest, settings: settings),
            lowestRemainingPercent: lowest,
            providers: providers
        )
    }

    static func lowestRemaining(in values: [String: ProviderUsage]) -> Double? {
        let candidates = values.values
            .filter { $0.status == .ok }
            .flatMap { usage in usage.windows().map { $0.remainingPercent } }
        return candidates.min()
    }

    static func gaugeState(lowest: Double?, settings: AppSettings) -> String {
        guard let lowest else { return "degraded" }
        if lowest < settings.criticalThreshold { return "critical" }
        if lowest < settings.warningThreshold { return "warning" }
        return "normal"
    }
}

/// Reads and writes the snapshot inside the shared App Group container.
public enum SnapshotStore {
    public static let appGroupID = "group.com.gmalbert.aiusagemonitor"
    public static let fileName = "usage-snapshot.json"

    public static func containerURL(for appGroupID: String = SnapshotStore.appGroupID) -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    public static func save(_ snapshot: UsageSnapshot, to appGroupID: String = SnapshotStore.appGroupID) throws {
        guard let container = containerURL(for: appGroupID) else {
            throw SnapshotStoreError(message: "App group container is unavailable")
        }
        let data = try JSONEncoder.withISODates().encode(snapshot)
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        let path = container.appendingPathComponent(fileName)
        let temporary = container.appendingPathComponent(".\(fileName).tmp")
        try data.write(to: temporary)
        if FileManager.default.fileExists(atPath: path.path) {
            _ = try FileManager.default.replaceItemAt(path, withItemAt: temporary)
        } else {
            try FileManager.default.moveItem(at: temporary, to: path)
        }
    }

    public static func load(from appGroupID: String = SnapshotStore.appGroupID) -> UsageSnapshot? {
        guard let container = containerURL(for: appGroupID),
              let data = try? Data(contentsOf: container.appendingPathComponent(fileName)) else {
            return nil
        }
        let snapshot = try? JSONDecoder.withISODates().decode(UsageSnapshot.self, from: data)
        if let snapshot, snapshot.schemaVersion == UsageSnapshot.schemaVersion {
            return snapshot
        }
        return nil
    }
}

public struct SnapshotStoreError: Error, CustomStringConvertible, Sendable {
    public let message: String
    public var description: String { message }
}
