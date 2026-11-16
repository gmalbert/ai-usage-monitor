import SwiftUI
import AIUsageMonitorCore

/// The full details window: every window with credits, reset times, ages,
/// and provider errors.
struct DetailsView: View {
    let store: AppStore
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if store.orderedProviders.isEmpty {
                        Text("Usage values are loading…")
                            .foregroundStyle(.secondary)
                            .padding(.top, 20)
                    }
                    ForEach(store.orderedProviders, id: \.provider) { usage in
                        ProviderCardView(
                            usage: usage,
                            compact: false,
                            warningThreshold: store.settings.warningThreshold,
                            criticalThreshold: store.settings.criticalThreshold,
                            onSetKey: usage.provider == "OpenCode Go" ? { openSettingsFromDetails() } : nil
                        )
                        if usage.provider != store.orderedProviders.last?.provider {
                            Divider()
                        }
                    }
                }
                .padding(18)
            }
        }
        .frame(minWidth: 560, minHeight: 430)
    }

    private func openSettingsFromDetails() {
        store.selectSettingsTab(.opencode)
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
    }

    private var header: some View {
        HStack {
            Text("AI Usage Monitor")
                .font(.title3.bold())
            Spacer()
            if let last = store.lastRefreshedAt {
                Text("Updated \(relativeAge(since: last))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Button {
                Task { await store.refresh() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(store.isRefreshing)
        }
        .padding(14)
    }
}
