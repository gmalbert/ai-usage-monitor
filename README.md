# AI Usage Monitor

AI Usage Monitor is a local Windows tray application and command-line utility for showing quota and credit usage from CommandCode, OpenCode Go, and Codex. It uses provider APIs or Codex's local app-server; it does not scrape browser interfaces and never copies secrets into its configuration or cache.

## Features

- CommandCode: 5-hour, weekly, and monthly-credit usage; plan, reset, and renewal times.
- OpenCode Go: 5-hour, weekly, and monthly percentages and reset times.
- Codex: live 5-hour and weekly limits through `codex app-server`, with a clearly marked local-session fallback when live access is unavailable.
- A tray gauge icon showing the lowest live remaining percentage. Its hover text shows CommandCode and OpenCode Go 5-hour and weekly values; Codex is shown there only when its live refresh succeeds.
- Concurrent refreshes every five minutes, manual refresh, independent provider failures, local-time timestamps, disk cache, rotating logs, threshold notifications, detailed window, and Start-with-Windows toggle.
- Human-readable and normalized JSON CLI modes for diagnostics or automation.

## Simple setup

You do **not** need to create or edit a configuration file.

1. Sign in to CommandCode and Codex normally, if you use them.
2. Build the app:

   ```powershell
   .\build_windows.ps1
   ```

3. Open `dist\AI Usage Monitor.exe`.

That is all. The app appears beside the clock in the Windows notification area. Right-click its icon to refresh, view details, add an OpenCode key, or turn on **Start with Windows**.

If you use OpenCode Go, right-click the tray icon and choose **Set OpenCode Go API key…**. Paste your key into the masked box and click **OK**. The monitor immediately refreshes OpenCode Go using the new key. The key is stored in Windows Credential Manager, not in a project file or the app settings. Use **Remove saved OpenCode Go API key** to delete it later.

If you only use CommandCode or Codex, skip the OpenCode Go key step.

## Tray behavior

- The gauge icon shows the lowest remaining percentage across available live provider windows. Green means at least 50% remains; amber means 20–49%; red means below 20%; gray means no live data is available.
- Hover over the icon to see `CommandCode: 5h … · Week …` and `OpenCode Go: 5h … · Week …`.
- Codex is omitted from hover text when it is unavailable, not configured, or using a stale local fallback so the compact display stays useful.
- **Refresh now** refreshes every configured provider without restarting the tray app.
- **Open detailed view** shows monthly values, reset times, credits, errors, and any stale-data notice.
- **Start with Windows** creates or removes the current user’s startup entry; no manual configuration is needed.

## Run from source

For development instead of the EXE:

```powershell
py -m pip install -r requirements.txt
py app.py --debug
```

The tray icon appears immediately and refreshes in the background every five minutes.

Run the CLI:

```powershell
py cli.py
py cli.py commandcode
py cli.py opencode --json
py cli.py codex
```

## Advanced settings (optional)

Normally, leave everything alone. The app creates its settings automatically when needed. The tray menu controls the only usual setting: **Start with Windows**.

If you specifically want to change how often it refreshes or when warnings appear, edit `%LOCALAPPDATA%\AIUsageMonitor\config.json` and use values such as:

```json
{
  "refresh_seconds": 300,
  "warning_threshold": 50,
  "critical_threshold": 20,
  "start_with_windows": false,
  "show_notifications": true
}
```

Do not put API keys in this file. OpenCode Go keys entered in the UI are stored separately in Windows Credential Manager. The app's cache and logs are kept under `%LOCALAPPDATA%\AIUsageMonitor`; they contain no credentials.

## Security

Credentials are never printed, logged, cached, added to configuration, or included in error messages. An OpenCode Go key entered through the UI is stored in Windows Credential Manager. CommandCode's `/alpha/` endpoints and plan mappings are isolated in `providers/commandcode.py`; OpenCode's endpoint is isolated in `providers/opencode.py`; Codex authentication remains inside the `codex app-server` process.

These provider interfaces are version-sensitive. A schema mismatch reports a clear provider-specific error and preserves the last successful cached values as stale data instead of blanking the monitor.

## Tests

Tests use fixtures/mocks only and make no live API calls:

```powershell
py -m unittest discover -s tests -v
```

They cover CommandCode plan and organization handling, the current ISO renewal-time format, OpenCode schema validation, Codex desktop executable discovery, malformed timestamps, zero caps, unknown plans, and HTTP 401/429 handling.

## Package as a single Windows executable

```powershell
.\build_windows.ps1
```

The script installs `requirements.txt` and PyInstaller into the same Python environment, then bundles `pystray` and its Windows backend. The executable is written to `dist\AI Usage Monitor.exe`.

To run the commands manually instead:

```powershell
py -m pip install -r requirements.txt pyinstaller
py -m PyInstaller --noconsole --onefile --name "AI Usage Monitor" --collect-all pystray app.py
```

During development, omit `--noconsole` so errors stay visible.

## Troubleshooting

- **CommandCode unavailable:** sign in to CommandCode again and verify `%USERPROFILE%\.commandcode\auth.json` contains its normal `apiKey` field.
- **CommandCode 403:** rebuild with the current source. The monitor now identifies itself to CommandCode; this resolves the API's rejection of Python's default network client identifier.
- **OpenCode authentication required:** right-click the tray icon and choose **Set OpenCode Go API key…**, then paste the key. You can remove it later from the same menu.
- **Codex unavailable:** the monitor automatically finds Codex installed with the desktop app. If it still cannot, install/sign in to Codex, then run `codex login status`. The monitor calls `codex app-server --stdio` for a live refresh, and the child command window stays hidden.
- **Codex marked “stale”:** the live Codex app-server did not respond, so the monitor is showing the latest usage snapshot saved locally by Codex. Open Codex normally to generate a newer local record, or restart the monitor after Codex is signed in. Stale Codex data is not shown in the tray hover text.
- **A provider reports a changed format:** its internal endpoint/schema changed. Update only that provider adapter; the other providers continue to refresh.
- **No desktop icon:** install the dependencies from `requirements.txt`, then run `py app.py --debug` to see local errors.
- **`ModuleNotFoundError: pystray` in the EXE:** delete the old executable in `dist`, then rebuild with ` .\build_windows.ps1`. This means PyInstaller was run before `pystray` was installed in that same Python environment.

macOS has the same provider/data model but requires a native SwiftUI `MenuBarExtra` shell for a production-quality menu-bar experience; this repository's runnable first release is the Windows/Python application.
