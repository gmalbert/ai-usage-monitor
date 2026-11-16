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
    There is one gauge per service — *AI Usage Gauge*, *AI Usage Gauge —
    CommandCode*, *AI Usage Gauge — Codex*, and *AI Usage Gauge — OpenCode
    Go* — so you can place several small gauges side by side, one per
    provider. They are separate widget kinds rather than an App Intents
    configuration option because macOS resolves intent parameters only for
    extensions signed with a team identifier, which ad-hoc local builds do
    not have.
  - *AI Providers* (medium/large): per-provider bars for 5-hour, weekly, and
    monthly, with a label row over the three columns.
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

This builds the app and widget extension and signs both bundles ad-hoc
(no Apple ID needed), then installs to `/Applications`. Then launch:

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

The widget reads the latest usage snapshot through the first channel that
works for the build (Settings → Diagnostics shows which one is active):

1. **App Group container** — when the build is provisioned for one (build
   with `--provisioned` and an Xcode account). The standard channel.
2. **Shared Keychain item** — for development-signed (non-ad-hoc) builds
   entitled to the shared keychain access group.
3. **Shared folder** — for local ad-hoc builds, which have no App Group
   provisioning and whose keychain access groups securityd cannot validate.
   The app publishes the snapshot as JSON at
   `/Users/Shared/AIUsageMonitor/usage-snapshot.json`, where the sandboxed
   widget reads it through a read-only sandbox exception declared in
   `UsageWidget.entitlements`.

The widget's sandbox is enforced even for ad-hoc builds: it cannot read the
real user home (its `homeDirectoryForCurrentUser` is its own container) and
its sandbox profile denies outbound network connections, so neither a file in
the app's cache directory nor the host app's loopback endpoint can serve it.

Every channel carries usage percentages and reset times only; no
credentials are ever included.

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

macOS caches each widget's descriptor (including its App Intents
configuration) per extension build. After adding or changing a widget in the
bundle, reinstall and restart the widget daemon so the new metadata is picked
up — otherwise the gallery keeps showing the old widget set:

```bash
killall chronod
```

Widget configuration parameters (`AppIntentConfiguration`) do not work in
these local builds: App Intents registers each intent with `linkd` under the
signing team identifier, and an ad-hoc signature has none (`Unable to get
teamId …`). That is why the per-provider gauges are separate widget kinds
rather than a `Provider` parameter.

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
- The menu-bar gauge is drawn with CoreGraphics into a non-template
  `NSImage`: SwiftUI shape strokes render monochrome inside `MenuBarExtra`
  labels on recent macOS versions, but colored NSImages render correctly.
- Keychain access is structured so no code path can surface a consent
  dialog: key presence is checked with a metadata-only query, and the
  stored key's data is only read after the user saves it with the running
  build (the item is created with an any-application-trusted ACL, so
  rebuilds never re-prompt). A key saved by an older build must be
  re-entered once; Settings shows a hint when that is the case.

## Signing for distribution

`./build_macos.sh` signs **ad-hoc by default** — it works without an Apple
ID and never touches the keychain, so it cannot trigger password or consent
prompts. Pass `--provisioned` to attempt automatic signing with the Xcode
account instead, which enables the App Group channel (requires an unlocked
login keychain and an Apple ID signed into Xcode):

```bash
./build_macos.sh Debug --install --provisioned
```

For sharing outside your Mac, re-sign with Developer ID and notarize, then
keep the App Group entitlement so the widget container channel activates:

```bash
codesign --force --sign "Developer ID Application: …" \
  --entitlements UsageWidget.entitlements \
  "/Applications/AI Usage Monitor.app/Contents/PlugIns/UsageWidget.appex"
codesign --force --sign "Developer ID Application: …" \
  --entitlements AIUsageMonitor.entitlements \
  "/Applications/AI Usage Monitor.app"
```
