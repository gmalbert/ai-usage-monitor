import WidgetKit
import SwiftUI
import AIUsageMonitorCore

/// Small widget: a large gauge of the lowest live remaining percentage for
/// one provider, or for every provider when `providerKey` is nil.
struct UsageGaugeWidgetView: View {
    let entry: SnapshotEntry
    let providerKey: String?

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
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Spacer()
                    if gaugeState == "degraded" {
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
                gauge
                Spacer(minLength: 0)
                footer
            }
            .padding(2)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else {
            emptyState
        }
    }

    private var selectedProvider: SnapshotProvider? {
        guard let providerKey, let snapshot = entry.snapshot else { return nil }
        return snapshot.providers.first { $0.key == providerKey }
    }

    private var title: String {
        selectedProvider?.name ?? "AI Usage"
    }

    /// The windows this gauge reflects: the widget's provider windows, or
    /// every live window across providers for the all-providers widget.
    private var windows: [SnapshotWindow] {
        if let provider = selectedProvider {
            return provider.windows
        }
        return entry.snapshot?.providers
            .filter { !$0.stale }
            .flatMap(\.windows) ?? []
    }

    private var lowest: Double? {
        windows.map(\.remainingPercent).min()
    }

    /// The provider window the gauge value comes from; nil for the
    /// all-providers gauge.
    private var lowestWindow: SnapshotWindow? {
        guard selectedProvider != nil else { return nil }
        return windows.min(by: { $0.remainingPercent < $1.remainingPercent })
    }

    private var gaugeState: String {
        guard selectedProvider != nil else {
            return entry.snapshot?.gaugeState ?? "degraded"
        }
        guard let lowest, let snapshot = entry.snapshot else { return "degraded" }
        if lowest < snapshot.criticalThreshold { return "critical" }
        if lowest < snapshot.warningThreshold { return "warning" }
        return "normal"
    }

    private var gauge: some View {
        HStack(alignment: .center, spacing: 10) {
            ZStack {
                Circle()
                    .stroke(.quinary, lineWidth: 6)
                if let lowest {
                    Circle()
                        .trim(from: 0, to: max(0.01, lowest / 100))
                        .stroke(
                            color(gaugeState),
                            style: StrokeStyle(lineWidth: 6, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                }
                Text(percentText)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
            .frame(width: 62, height: 62)
            VStack(alignment: .leading, spacing: 2) {
                Text(gaugeLabel)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("remaining")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// "Lowest" for the all-providers gauge; the window name — for example
    /// "Weekly" — for a single-provider gauge, so the number is labeled with
    /// what it measures.
    private var gaugeLabel: String {
        guard selectedProvider != nil else { return "Lowest" }
        return lowestWindow?.name ?? "No window"
    }

    @ViewBuilder
    private var footer: some View {
        if let text = footerText {
            Text(text)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
    }

    /// The plan (and staleness) for a single-provider gauge — the window name
    /// already labels the gauge — or the tightest live window overall for the
    /// all-providers gauge.
    private var footerText: String? {
        if let provider = selectedProvider {
            if provider.windows.isEmpty {
                return provider.statusMessage
            }
            var parts: [String] = []
            if let plan = provider.plan, !plan.isEmpty {
                parts.append(plan)
            }
            if provider.stale {
                parts.append("stale")
            }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        }
        let liveMeters = (entry.snapshot?.providers ?? [])
            .filter { !$0.stale }
            .flatMap { provider in provider.windows.map { (provider.name, $0) } }
        guard let worst = liveMeters.min(by: { $0.1.remainingPercent < $1.1.remainingPercent }) else {
            return nil
        }
        return "\(worst.1.name) · \(worst.0)"
    }

    private var percentText: String {
        if let lowest {
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
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
            Spacer()
            Text("Open AI Usage Monitor to publish usage data.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Shared shape for the gauge widgets. Each provider gets its own widget
/// kind instead of an App Intents configuration parameter: WidgetKit only
/// resolves intent parameters through system App Intents services, which
/// refuse extensions signed without a team identifier — every locally
/// signed (ad-hoc) build.
private func gaugeConfiguration(
    kind: String,
    providerKey: String?,
    displayName: LocalizedStringKey,
    widgetDescription: LocalizedStringKey
) -> some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: SnapshotTimelineProvider()) { entry in
        UsageGaugeWidgetView(entry: entry, providerKey: providerKey)
    }
    .configurationDisplayName(displayName)
    .description(widgetDescription)
    .supportedFamilies([.systemSmall])
}

struct UsageGaugeWidget: Widget {
    var body: some WidgetConfiguration {
        gaugeConfiguration(
            kind: WidgetKinds.gauge,
            providerKey: nil,
            displayName: "AI Usage Gauge",
            widgetDescription: "The lowest remaining quota across all providers."
        )
    }
}

struct CommandCodeGaugeWidget: Widget {
    var body: some WidgetConfiguration {
        gaugeConfiguration(
            kind: WidgetKinds.gaugeCommandCode,
            providerKey: "commandcode",
            displayName: "AI Usage Gauge — CommandCode",
            widgetDescription: "CommandCode's lowest remaining quota."
        )
    }
}

struct CodexGaugeWidget: Widget {
    var body: some WidgetConfiguration {
        gaugeConfiguration(
            kind: WidgetKinds.gaugeCodex,
            providerKey: "codex",
            displayName: "AI Usage Gauge — Codex",
            widgetDescription: "Codex's lowest remaining quota."
        )
    }
}

struct OpenCodeGaugeWidget: Widget {
    var body: some WidgetConfiguration {
        gaugeConfiguration(
            kind: WidgetKinds.gaugeOpenCode,
            providerKey: "opencode",
            displayName: "AI Usage Gauge — OpenCode Go",
            widgetDescription: "OpenCode Go's lowest remaining quota."
        )
    }
}
