import SwiftUI

@main
struct AIUsageMonitorApp: App {
    @State private var store = AppStore()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(store: store)
        } label: {
            GaugeLabelView(state: store.gaugeState, remaining: store.lowestRemaining)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(store: store)
        }

        Window("Usage Details", id: "details") {
            DetailsView(store: store)
                .frame(minWidth: 520, minHeight: 420)
                .onOpenURL { url in
                    guard url.absoluteString == "aiusagemonitor://details" else { return }
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
        .windowResizability(.contentSize)
    }
}
