import WidgetKit
import SwiftUI
import AIUsageMonitorCore

/// Medium widget: every provider with its 5-hour, weekly, and monthly bars.
struct UsageProvidersWidgetView: View {
    let entry: SnapshotEntry

    var body: some View {
        content
            .widgetURL(URL(string: "aiusagemonitor://details"))
    }

    @ViewBuilder
    private var content: some View {
        if let snapshot = entry.snapshot {
            VStack(alignment: .leading, spacing: 7) {
                header(snapshot)
                ForEach(snapshot.providers, id: \.key) { provider in
                    providerRow(provider)
                }
            }
            .padding(2)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("AI Usage")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("Open AI Usage Monitor to publish usage data.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func header(_ snapshot: UsageSnapshot) -> some View {
        HStack {
            Image(systemName: "gauge.with.needle")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("AI Usage")
                .font(.system(size: 12, weight: .semibold))
            Spacer()
            Text(relativeAge(since: snapshot.savedAt, from: entry.date))
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private func providerRow(_ provider: SnapshotProvider) -> some View {
        if provider.windows.isEmpty {
            HStack(spacing: 6) {
                nameColumn(provider.name, stale: provider.stale)
                Text(provider.statusMessage ?? "Unavailable")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
        } else {
            HStack(spacing: 6) {
                nameColumn(provider.name, stale: provider.stale)
                ForEach(Array(meters(provider).enumerated()), id: \.offset) { _, meter in
                    meterBar(meter)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func nameColumn(_ name: String, stale: Bool) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(stale ? Color.orange : Color.green)
                .frame(width: 4, height: 4)
            Text(name)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
        }
        .frame(width: 86, alignment: .leading)
    }

    private func meters(_ provider: SnapshotProvider) -> [SnapshotWindow] {
        let preferred = ["5-hour", "Weekly", "Monthly"]
        return preferred.compactMap { name in provider.windows.first { $0.name == name } }
    }

    private func meterBar(_ window: SnapshotWindow) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quinary)
                    Capsule()
                        .fill(barColor(window.remainingPercent))
                        .frame(width: max(2, proxy.size.width * window.remainingPercent / 100))
                }
            }
            .frame(height: 4)
            Text("\(Int(window.remainingPercent.rounded()))%")
                .font(.system(size: 8, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .frame(width: 44)
    }

    private func barColor(_ remaining: Double) -> Color {
        if remaining < 20 { return .red }
        if remaining < 50 { return .orange }
        return .green
    }
}

struct UsageProvidersWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKinds.providers, provider: SnapshotTimelineProvider()) { entry in
            UsageProvidersWidgetView(entry: entry)
        }
        .configurationDisplayName("AI Providers")
        .description("Remaining quota per provider across 5-hour, weekly, and monthly windows.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}
