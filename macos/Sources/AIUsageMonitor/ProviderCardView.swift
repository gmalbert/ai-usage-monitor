import SwiftUI
import AIUsageMonitorCore

/// One usage window row: label, remaining bar, percent, reset countdown.
struct MeterRowView: View {
    let window: UsageWindow
    let compact: Bool
    var warningThreshold: Double = 50
    var criticalThreshold: Double = 20

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(window.name)
                .font(.system(size: compact ? 11 : 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: compact ? 52 : 64, alignment: .leading)
            bar
                .frame(height: compact ? 5 : 6)
            Text("\(Int(window.remainingPercent.rounded()))%")
                .font(.system(size: compact ? 11 : 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .frame(width: 36, alignment: .trailing)
            if !compact {
                Text(resetText)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(window.name): \(Int(window.remainingPercent.rounded())) percent remaining")
    }

    private var bar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.quinary)
                Capsule()
                    .fill(color)
                    .frame(width: max(2, proxy.size.width * window.remainingPercent / 100))
            }
        }
    }

    private var color: Color {
        let state: String
        if window.remainingPercent < criticalThreshold {
            state = "critical"
        } else if window.remainingPercent < warningThreshold {
            state = "warning"
        } else {
            state = "normal"
        }
        return GaugePalette.color(for: state)
    }

    private var resetText: String {
        guard let resetAt = window.resetAt else { return "" }
        return relativeCountdown(to: resetAt)
    }
}

/// A provider section with its plan, live/stale state, meters, and errors.
struct ProviderCardView: View {
    let usage: ProviderUsage
    let compact: Bool
    var warningThreshold: Double = 50
    var criticalThreshold: Double = 20

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            if usage.stale {
                Label(staleExplanation, systemImage: "clock.arrow.circlepath")
                    .font(.system(size: compact ? 10 : 11))
                    .foregroundStyle(.orange)
            }
            ForEach(usage.windows(), id: \.name) { window in
                MeterRowView(
                    window: window,
                    compact: compact,
                    warningThreshold: warningThreshold,
                    criticalThreshold: criticalThreshold
                )
            }
            if usage.windows().isEmpty {
                Text(usage.error ?? usage.status.label)
                    .font(.system(size: compact ? 11 : 12))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            extras
        }
        .padding(.vertical, 4)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(usage.provider)
                .font(.system(size: compact ? 12 : 13, weight: .semibold))
            if let plan = usage.plan {
                Text(plan)
                    .font(.system(size: compact ? 10 : 11, weight: .medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quinary, in: Capsule())
            }
            Spacer()
            statusBadge
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch usage.status {
        case .ok:
            Label("Live", systemImage: "checkmark.circle.fill")
                .labelStyle(.titleAndIcon)
                .font(.system(size: compact ? 10 : 11, weight: .medium))
                .foregroundStyle(.green)
        case .stale, .staleLogFallback:
            Text("Stale · \(relativeAge(since: usage.fetchedAt))")
                .font(.system(size: compact ? 10 : 11))
                .foregroundStyle(.orange)
        default:
            Text(usage.status.label)
                .font(.system(size: compact ? 10 : 11))
                .foregroundStyle(.secondary)
        }
    }

    /// Provider-specific stale explanations instead of the reference
    /// implementation's single Codex-specific message.
    private var staleExplanation: String {
        if usage.provider == "Codex" {
            return "Latest local Codex record; live refresh unavailable \(relativeAge(since: usage.fetchedAt))."
        }
        return "Cached values; the last live refresh failed \(relativeAge(since: usage.fetchedAt))."
    }

    @ViewBuilder
    private var extras: some View {
        if let balance = usage.creditBalance, !compact {
            Text("Extra credits: $\(String(format: "%.2f", balance)) remaining")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        if let resets = usage.resetCreditsAvailable, resets > 0 {
            Text("Rate-limit resets available: \(resets)")
                .font(.system(size: compact ? 10 : 11))
                .foregroundStyle(.secondary)
        }
    }
}
