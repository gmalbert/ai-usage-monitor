import WidgetKit
import SwiftUI
import AIUsageMonitorCore

/// Medium widget: every provider with its 5-hour, weekly, and monthly bars.
struct UsageProvidersWidgetView: View {
    let entry: SnapshotEntry

    private static let windowColumns: [(name: String, label: String)] = [
        ("5-hour", "5-hour"),
        ("Weekly", "Weekly"),
        ("Monthly", "Monthly"),
    ]
    private static let nameColumnWidth: CGFloat = 86
    private static let meterColumnWidth: CGFloat = 44
    private static let columnSpacing: CGFloat = 6

    var body: some View {
        content
            .widgetURL(URL(string: "aiusagemonitor://details"))
    }

    @ViewBuilder
    private var content: some View {
        if let snapshot = entry.snapshot {
            VStack(alignment: .leading, spacing: 7) {
                header(snapshot)
                columnHeader
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

    /// Column labels aligned with the meter columns of every provider row.
    private var columnHeader: some View {
        HStack(spacing: Self.columnSpacing) {
            Color.clear.frame(width: Self.nameColumnWidth, height: 1)
            ForEach(Self.windowColumns, id: \.name) { column in
                Text(column.label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(width: Self.meterColumnWidth, alignment: .leading)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func providerRow(_ provider: SnapshotProvider) -> some View {
        if provider.windows.isEmpty {
            HStack(spacing: Self.columnSpacing) {
                nameColumn(provider.name, stale: provider.stale)
                Text(provider.statusMessage ?? "Unavailable")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
        } else {
            HStack(spacing: Self.columnSpacing) {
                nameColumn(provider.name, stale: provider.stale)
                ForEach(Self.windowColumns, id: \.name) { column in
                    if let window = provider.windows.first(where: { $0.name == column.name }) {
                        meterBar(window)
                    } else {
                        // Keep the missing column's space so providers without
                        // a window (for example Codex without a monthly limit)
                        // stay aligned under the labels.
                        Color.clear.frame(width: Self.meterColumnWidth, height: 1)
                    }
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
        .frame(width: Self.nameColumnWidth, alignment: .leading)
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
        .frame(width: Self.meterColumnWidth)
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
