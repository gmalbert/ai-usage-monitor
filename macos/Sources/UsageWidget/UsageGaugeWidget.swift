import WidgetKit
import SwiftUI
import AIUsageMonitorCore

/// Small widget: a large gauge of the lowest live remaining percentage.
struct UsageGaugeWidgetView: View {
    let entry: SnapshotEntry

    var body: some View {
        content
            .widgetURL(URL(string: "aiusagemonitor://details"))
    }

    @ViewBuilder
    private var content: some View {
        if let snapshot = entry.snapshot {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "gauge.with.needle")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("AI Usage")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    if snapshot.gaugeState == "degraded" {
                        Text("No data")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    } else {
                        Text(relativeAge(since: snapshot.savedAt, from: entry.date))
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer(minLength: 0)
                gauge(snapshot)
                Spacer(minLength: 0)
                footer(snapshot)
            }
            .padding(2)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else {
            emptyState
        }
    }

    private func gauge(_ snapshot: UsageSnapshot) -> some View {
        HStack(alignment: .center, spacing: 10) {
            ZStack {
                Circle()
                    .stroke(.quinary, lineWidth: 6)
                if let lowest = snapshot.lowestRemainingPercent {
                    Circle()
                        .trim(from: 0, to: max(0.01, lowest / 100))
                        .stroke(
                            color(snapshot.gaugeState),
                            style: StrokeStyle(lineWidth: 6, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                }
                Text(percentText(snapshot))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
            .frame(width: 62, height: 62)
            VStack(alignment: .leading, spacing: 2) {
                Text("Lowest")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text("remaining")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func footer(_ snapshot: UsageSnapshot) -> some View {
        let liveMeters = snapshot.providers
            .filter { !$0.stale }
            .flatMap { provider in provider.windows.map { (provider.name, $0) } }
        if let worst = liveMeters.min(by: { $0.1.remainingPercent < $1.1.remainingPercent }) {
            Text("\(worst.1.name) · \(worst.0)")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        } else {
            Text("Open AI Usage Monitor to publish usage data")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }

    private func percentText(_ snapshot: UsageSnapshot) -> String {
        if let lowest = snapshot.lowestRemainingPercent {
            "\(Int(lowest.rounded()))%"
        } else {
            "—"
        }
    }

    private func color(_ state: String) -> Color {
        switch state {
        case "normal": .green
        case "warning": .orange
        case "critical": .red
        default: .gray
        }
    }

    private var emptyState: some View {
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

struct UsageGaugeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKinds.gauge, provider: SnapshotTimelineProvider()) { entry in
            UsageGaugeWidgetView(entry: entry)
        }
        .configurationDisplayName("AI Usage Gauge")
        .description("The lowest remaining quota across your AI providers.")
        .supportedFamilies([.systemSmall])
    }
}
