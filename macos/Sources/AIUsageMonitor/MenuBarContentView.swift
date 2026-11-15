import SwiftUI
import AIUsageMonitorCore

/// The menu-bar popover: quick glance at every provider plus actions.
struct MenuBarContentView: View {
    let store: AppStore
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if store.orderedProviders.isEmpty {
                        Text("Usage values are loading…")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                    }
                    let providers = store.orderedProviders
                    ForEach(Array(providers.enumerated()), id: \.element.provider) { index, usage in
                        ProviderCardView(
                            usage: usage,
                            compact: true,
                            warningThreshold: store.settings.warningThreshold,
                            criticalThreshold: store.settings.criticalThreshold,
                            onSetKey: usage.provider == "OpenCode Go" ? { openSettings(to: .opencode) } : nil
                        )
                        if index < providers.count - 1 {
                            Divider().padding(.vertical, 2)
                        }
                    }
                    if store.snapshotChannel == "loopback" {
                        Text("Widget sync: local fallback (no App Group or Keychain)")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
            .frame(maxHeight: 360)
            Divider()
            footer
        }
        .frame(width: 340)
        .onAppear {
            // Refresh when the popover opens if the data is older than one
            // refresh interval; scheduled refreshes continue in the background.
            if let last = store.lastRefreshedAt,
               Date().timeIntervalSince(last) > Double(store.settings.refreshSeconds) {
                Task { await store.refresh() }
            }
        }
    }

    private var header: some View {
        HStack {
            Text("AI Usage Monitor")
                .font(.system(size: 13, weight: .bold))
            Spacer()
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Button {
                Task { await store.refresh() }
            } label: {
                if store.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderless)
            .help("Refresh now")
            .disabled(store.isRefreshing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var subtitle: String {
        if store.isRefreshing {
            return "Refreshing…"
        }
        if let last = store.lastRefreshedAt {
            return "Updated \(relativeAge(since: last))"
        }
        return "No data yet"
    }

    private var footer: some View {
        HStack {
            Button("Settings…") {
                openSettings(to: .general)
            }
            .buttonStyle(.borderless)
            .font(.system(size: 12))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            Spacer()
            Button("Details") {
                NSApp.activate(ignoringOtherApps: true)
                NSWorkspace.shared.open(URL(string: "aiusagemonitor://details")!)
            }
            .buttonStyle(.borderless)
            .font(.system(size: 12))
            Button("Quit") {
                NSApp.terminate(nil)
            }
            .buttonStyle(.borderless)
            .font(.system(size: 12))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    /// Activates the app and opens Settings on the requested tab. Menu-bar
    /// apps are not active while the popover is open, and the Settings
    /// window would otherwise stay in the background.
    private func openSettings(to tab: AppStore.SettingsTab) {
        store.selectSettingsTab(tab)
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
    }
}
