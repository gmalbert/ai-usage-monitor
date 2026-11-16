import WidgetKit
import SwiftUI
import os
import AIUsageMonitorCore

private let logger = Logger(subsystem: "com.gmalbert.aiusagemonitor.UsageWidget", category: "snapshot")

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot?

    static let placeholder = SnapshotEntry(
        date: Date(),
        snapshot: SnapshotEntry.sampleSnapshot
    )

    static var sampleSnapshot: UsageSnapshot {
        UsageSnapshot(
            savedAt: Date(),
            refreshSeconds: 300,
            gaugeState: "normal",
            lowestRemainingPercent: 64,
            providers: [
                SnapshotProvider(
                    key: "commandcode",
                    name: "CommandCode",
                    plan: "GOAT",
                    stale: false,
                    statusMessage: "Live",
                    windows: [
                        SnapshotWindow(name: "5-hour", usedPercent: 31, remainingPercent: 69, resetAt: Date().addingTimeInterval(2 * 3_600)),
                        SnapshotWindow(name: "Weekly", usedPercent: 27, remainingPercent: 73, resetAt: Date().addingTimeInterval(3 * 86_400)),
                        SnapshotWindow(name: "Monthly", usedPercent: 49, remainingPercent: 51, resetAt: Date().addingTimeInterval(10 * 86_400)),
                    ],
                    creditBalance: nil,
                    resetCreditsAvailable: nil
                ),
                SnapshotProvider(
                    key: "codex",
                    name: "Codex",
                    plan: "Plus",
                    stale: true,
                    statusMessage: "Stale",
                    windows: [
                        SnapshotWindow(name: "5-hour", usedPercent: 36, remainingPercent: 64, resetAt: Date().addingTimeInterval(4 * 3_600)),
                        SnapshotWindow(name: "Weekly", usedPercent: 12, remainingPercent: 88, resetAt: Date().addingTimeInterval(5 * 86_400)),
                    ],
                    creditBalance: 0,
                    resetCreditsAvailable: 3
                ),
                SnapshotProvider(
                    key: "opencode",
                    name: "OpenCode Go",
                    plan: "Go",
                    stale: false,
                    statusMessage: "Live",
                    windows: [
                        SnapshotWindow(name: "5-hour", usedPercent: 5, remainingPercent: 95, resetAt: Date().addingTimeInterval(3 * 3_600)),
                        SnapshotWindow(name: "Weekly", usedPercent: 20, remainingPercent: 80, resetAt: Date().addingTimeInterval(6 * 86_400)),
                        SnapshotWindow(name: "Monthly", usedPercent: 30, remainingPercent: 70, resetAt: Date().addingTimeInterval(12 * 86_400)),
                    ],
                    creditBalance: nil,
                    resetCreditsAvailable: nil
                ),
            ]
        )
    }
}

struct SnapshotTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(
            date: Date(),
            snapshot: SnapshotTimelineProvider.loadSnapshot() ?? SnapshotEntry.sampleSnapshot
        ))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let snapshot = SnapshotTimelineProvider.loadSnapshot()
        let now = Date()
        let interval = snapshot?.refreshSeconds ?? 300
        // Two entries: the data is re-read from the shared store when the
        // second entry is generated, so the widget tracks the app's cadence.
        let timeline = Timeline(
            entries: [
                SnapshotEntry(date: now, snapshot: snapshot),
                SnapshotEntry(date: now.addingTimeInterval(TimeInterval(interval)), snapshot: snapshot),
            ],
            policy: .after(now.addingTimeInterval(TimeInterval(interval)))
        )
        completion(timeline)
    }

    /// Channel order: the shared App Group container, then the shared
    /// Keychain item (entitled development-signed builds), then the
    /// `/Users/Shared` file that local ad-hoc builds publish to.
    ///
    /// The host app's loopback endpoint is not a usable channel here: widget
    /// extensions are sandboxed and their profile denies outbound network
    /// connections even with `com.apple.security.network-client`.
    static func loadSnapshot() -> UsageSnapshot? {
        if let snapshot = SnapshotStore.load() {
            logger.notice("Widget snapshot channel: app-group")
            return snapshot
        }
        // Only read the shared keychain item when this binary is entitled
        // to its access group; an unauthorized read would trigger a keychain
        // ACL consent prompt on every refresh.
        if SharedSnapshotStore.selfEntitled(), let snapshot = SharedSnapshotStore.load() {
            logger.notice("Widget snapshot channel: keychain")
            return snapshot
        }
        if let snapshot = SharedFolderSnapshotStore.load() {
            logger.notice("Widget snapshot channel: shared-folder")
            return snapshot
        }
        logger.notice("Widget snapshot channel: none (no snapshot available)")
        return nil
    }
}
