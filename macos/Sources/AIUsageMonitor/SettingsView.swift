import SwiftUI
import AIUsageMonitorCore

/// Settings window: general behavior, the OpenCode Go key, and diagnostics.
struct SettingsView: View {
    let store: AppStore

    var body: some View {
        TabView {
            GeneralSettingsTab(store: store)
                .tabItem { Label("General", systemImage: "gearshape") }
            OpenCodeKeySettingsTab(store: store)
                .tabItem { Label("OpenCode Go", systemImage: "key") }
            DiagnosticsSettingsTab(store: store)
                .tabItem { Label("Diagnostics", systemImage: "stethoscope") }
        }
        .frame(width: 460)
    }
}

private struct GeneralSettingsTab: View {
    let store: AppStore
    @State private var loginAtLogin = LoginItemController.isEnabled

    var body: some View {
        Form {
            Picker("Refresh interval", selection: intervalBinding) {
                ForEach([60, 300, 600, 900, 1800], id: \.self) { seconds in
                    Text(intervalLabel(seconds)).tag(seconds)
                }
            }
            LabeledContent("Warning below") {
                Slider(value: warningBinding, in: 10...90, step: 5) {
                    Text("Warning threshold")
                }
                Text("\(Int(store.settings.warningThreshold))%")
                    .monospacedDigit()
                    .frame(width: 40, alignment: .trailing)
            }
            LabeledContent("Critical below") {
                Slider(value: criticalBinding, in: 5...50, step: 5) {
                    Text("Critical threshold")
                }
                Text("\(Int(store.settings.criticalThreshold))%")
                    .monospacedDigit()
                    .frame(width: 40, alignment: .trailing)
            }
            Toggle("Threshold notifications", isOn: notificationsBinding)
            Toggle("Launch at login", isOn: $loginAtLogin)
                .onChange(of: loginAtLogin) { _, enabled in
                    store.toggleLaunchAtLogin(enabled)
                }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var intervalBinding: Binding<Int> {
        Binding(
            get: { store.settings.refreshSeconds },
            set: { seconds in
                store.update(settings: withSettings { $0.refreshSeconds = seconds })
            }
        )
    }

    private var warningBinding: Binding<Double> {
        Binding(
            get: { store.settings.warningThreshold },
            set: { value in
                store.update(settings: withSettings { $0.warningThreshold = value })
            }
        )
    }

    private var criticalBinding: Binding<Double> {
        Binding(
            get: { store.settings.criticalThreshold },
            set: { value in
                store.update(settings: withSettings { $0.criticalThreshold = min(value, store.settings.warningThreshold - 1) })
            }
        )
    }

    private var notificationsBinding: Binding<Bool> {
        Binding(
            get: { store.settings.showNotifications },
            set: { enabled in
                store.update(settings: withSettings { $0.showNotifications = enabled })
            }
        )
    }

    private func withSettings(_ mutate: (inout AppSettings) -> Void) -> AppSettings {
        var settings = store.settings
        mutate(&settings)
        return settings
    }

    private func intervalLabel(_ seconds: Int) -> String {
        let minutes = seconds / 60
        return minutes < 1 ? "\(seconds) seconds" : "\(minutes) minute\(minutes == 1 ? "" : "s")"
    }
}

private struct OpenCodeKeySettingsTab: View {
    let store: AppStore
    @State private var key = ""
    @State private var statusMessage: String?

    var body: some View {
        Form {
            LabeledContent("Saved key") {
                if store.opencodeKeyPresent {
                    Label("Stored in Keychain", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                } else {
                    Text("None").foregroundStyle(.secondary)
                }
            }
            SecureField("OpenCode Go API key", text: $key)
                .onSubmit(save)
            HStack {
                Button("Save", action: save)
                    .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Remove saved key", role: .destructive) {
                    store.removeOpencodeKey()
                    statusMessage = "The saved key was removed."
                    key = ""
                }
                .disabled(!store.opencodeKeyPresent)
            }
            if let statusMessage {
                Text(statusMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Text("The key is stored only in the macOS Keychain — never in settings files, the cache, or logs. If the OPENCODE_GO_API_KEY environment variable or an existing OpenCode auth file is present, it is used when no key is saved.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding()
        .onAppear { key = "" }
    }

    private func save() {
        do {
            try store.saveOpencodeKey(key)
            statusMessage = "Saved securely in the Keychain."
            key = ""
        } catch {
            statusMessage = "Could not save the key: \(error.localizedDescription)"
        }
    }
}

private struct DiagnosticsSettingsTab: View {
    let store: AppStore

    var body: some View {
        Form {
            LabeledContent("Cache") {
                Button("Reveal in Finder") { reveal(UsageCache.defaultPath()) }
            }
            LabeledContent("Logs") {
                Button("Reveal in Finder") { reveal(RotatingFileLog.shared.directory) }
            }
            LabeledContent("Widget data") {
                if store.snapshotChannel == "app-group" {
                    Label("Shared container", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Label("Local fallback", systemImage: "arrow.triangle.2.circlepath")
                        .foregroundStyle(.orange)
                }
            }
            Text("The widget reads the shared App Group container when your build is provisioned with one; otherwise the app serves the snapshot over a localhost-only channel for the widget.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding()
    }

    private func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
