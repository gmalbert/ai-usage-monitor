import WidgetKit
import SwiftUI
import AIUsageMonitorCore

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
        Task {
            completion(SnapshotEntry(date: Date(), snapshot: await loadSnapshot() ?? SnapshotEntry.sampleSnapshot))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        Task {
            let snapshot = await loadSnapshot()
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
    }

    /// Channel order: the shared App Group container, then the shared
    /// Keychain item (works for development-signed builds without a
    /// provisioning profile), then the host app's loopback endpoint.
    private func loadSnapshot() async -> UsageSnapshot? {
        if let snapshot = SnapshotStore.load() {
            return snapshot
        }
        // Only read the shared keychain item when this binary is entitled
        // to its access group; an unauthorized read would trigger a keychain
        // ACL consent prompt on every refresh.
        if SharedSnapshotStore.selfEntitled(), let snapshot = SharedSnapshotStore.load() {
            return snapshot
        }
        var request = URLRequest(url: LocalSnapshotSync.url)
        request.timeoutInterval = 3
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else {
            return nil
        }
        return try? JSONDecoder.withISODates().decode(UsageSnapshot.self, from: data)
    }
}
