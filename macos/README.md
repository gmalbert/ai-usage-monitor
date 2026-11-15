# AI Usage Monitor — macOS

A native menu-bar (tray) app with a matching desktop widget, ported from the
Windows/Python implementation in this repository. It shows live quota usage
for CommandCode, OpenCode Go, and Codex without scraping browsers or storing
secrets in files.

## What it does

- **Menu-bar gauge** showing the lowest remaining percentage across live
  provider windows. Green ≥ 50 %, amber 20–49 %, red < 20 %, gray when no
  live data exists.
- **Popover with provider cards**: 5-hour, weekly, and monthly remaining
  percentages, reset times and countdowns, credits, plan, live/stale state,
  and per-provider errors.
- **Desktop widget** (macOS 15+ can pin widgets to the desktop; on macOS 14
  the same widgets appear in Notification Center):
  - *AI Usage Gauge* (small): circular gauge with the lowest remaining value.
  - *AI Providers* (medium): per-provider bars for 5-hour, weekly, monthly.
- Refresh at startup, every 5 minutes (configurable), manually, and after
  system wake. Provider fetches run concurrently; one provider failing never
  hides the others, and the last successful values are kept and marked stale.
- **Threshold notifications** fire once when a meter crosses downward into
  warning/critical territory, using live data only.
- **OpenCode Go key management** in Settings, stored in the macOS Keychain —
  never in UserDefaults, config files, cache, or logs.
- **Launch at login** through `SMAppService`.
- Cache at `~/Library/Caches/AIUsageMonitor/cache.json`, rotating logs at
  `~/Library/Logs/AIUsageMonitor/`.

## Requirements

- macOS 14.0 or newer (desktop widget placement requires macOS 15+)
- Xcode 27 with the Swift 6.4 toolchain (older Xcodes that support Swift 5
  and macOS 14 deployment targets should also work)
- [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Build and run

```bash
cd macos
xcodegen generate --spec project.yml   # once, and after adding files
./build_macos.sh Debug --install
```

This builds the app and widget extension unsigned, then signs both bundles
with your local development identity (or ad-hoc when none exists) and
installs to `/Applications`. Then launch:

```bash
open "/Applications/AI Usage Monitor.app"
```

Or build without installing:

```bash
./build_macos.sh Debug        # product in macos/build/DerivedData/...
```

The menu-bar item appears immediately and refreshes in the background.

## Add the widget

1. Launch the app at least once so it publishes a snapshot.
2. Right-click the desktop → **Edit Widgets…** (or Notification Center →
   **Edit Widgets**).
3. Search for **AI Usage** and add *AI Usage Gauge* or *AI Providers*.

Clicking the widget opens the app's details window.

## Data channel used by the widget

The widget reads the latest usage snapshot from the shared App Group
container when your build is provisioned for one (Xcode automatic signing
with an Apple ID selected in Xcode → Signing & Capabilities). On development
builds without a provisioning profile — where macOS refuses group container
access — the app additionally serves the identical snapshot on a
**loopback-only** HTTP endpoint (`127.0.0.1:52317`), which the sandboxed
widget fetches as a fallback. The endpoint carries usage percentages and
reset times only; no credentials are ever included. Settings → Diagnostics
shows which channel is active.

## Development

The shared logic lives in an SPM package (`Sources/AIUsageMonitorCore`)
that both the app target and the widget extension depend on. Core is
unit-tested with fixture data — no live API calls:

```bash
cd macos
swift test
```

Run from Xcode: `open AIUsageMonitor.xcodeproj`, pick the AIUsageMonitor
scheme. Regenerate the project after adding or removing source files:

```bash
xcodegen generate --spec project.yml
```

### Architecture

| Target | Contents |
| --- | --- |
| `AIUsageMonitorCore` | Models, normalization, provider adapters (CommandCode, OpenCode Go, Codex app-server + stale fallback), refresh service, cache, snapshot, Keychain store, settings |
| `AIUsageMonitor` | SwiftUI `MenuBarExtra` app, popover/details/settings UI, notifications, login item, rotating log, snapshot server |
| `UsageWidget` | WidgetKit extension: gauge + providers widgets, timeline that reads the shared snapshot |

Behavior notes beyond the Windows app:

- Refreshes are serialized through the `UsageService` actor; manual and
  scheduled refreshes cannot overlap.
- Cached values load as *stale* at startup — they can never masquerade as
  fresh data.
- Codex executable discovery checks `PATH`, common install directories, and
  the verified Codex desktop bundle layout
  (`ChatGPT.app/Contents/Resources/codex-cli/bin/codex`).
- Codex stale fallback preserves the session record's real observation time
  and shows its age.

## Signing for distribution

Local builds sign with a development identity or ad-hoc; the App Group works
once Xcode provisions it. For sharing outside your Mac, re-sign with Developer
ID and notarize, then keep the App Group entitlement so the widget container
channel activates:

```bash
codesign --force --sign "Developer ID Application: …" \
  --entitlements UsageWidget.entitlements \
  "/Applications/AI Usage Monitor.app/Contents/PlugIns/UsageWidget.appex"
codesign --force --sign "Developer ID Application: …" \
  --entitlements AIUsageMonitor.entitlements \
  "/Applications/AI Usage Monitor.app"
```
