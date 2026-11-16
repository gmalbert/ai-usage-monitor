# Mac development handoff

Prepared November 15, 2026. This is a development handoff, not a claim that the app currently supports macOS.

> **Status update (November 15, 2026):** the Mac implementation described in
> this document is complete. `macos/` now contains the native SwiftUI
> menu-bar app, the WidgetKit desktop widget, the Swift core port with
> fixture-based tests, and the `build_macos.sh` build/sign/install script.
> Baseline validation: Python suite 14/14 on this Mac (Python 3.12.16), core
> Swift tests green via `swift test`, app live-refreshed all three providers
> (CommandCode live, Codex live via the ChatGPT.app bundle binary, OpenCode
> awaiting a Keychain key). Build with Xcode 27.2, deployment target macOS 14.
> The App Group container requires a provisioned build (Xcode automatic
> signing); without it, the widget falls back to the app's loopback-only
> snapshot channel. See `macos/README.md`.

## Start here

Continue development of AI Usage Monitor on a Mac by building a native menu-bar app while preserving the working Windows application. The existing plan favors SwiftUI `MenuBarExtra`; there is no Swift/Xcode project in this checkout yet. Use the Python implementation as the behavior and provider-contract reference.

- Repository: https://github.com/gmalbert/ai-usage-monitor
- Baseline branch: `main`
- Baseline commit: `b66bdbcd98209892ca2c7e08c6284603d8b904c7`
- Working tree was clean before this handoff was added.
- Validation on Windows: Python 3.13.15, `python -m unittest discover -s tests -v`, **14 tests passed**.
- Mac execution, native builds, signing, and live provider access have not been validated for this handoff.

Read this document first, then the relevant implementation files. `docs/ai_usage_monitor_plan.md` contains the earlier architecture and Mac UI proposal, but portions describe historical plans rather than current behavior. Prefer current source when they disagree.

## Get started on the Mac

Have Git, a separately installed Python 3.13 interpreter, and Xcode available. Python 3.13 matches the validated baseline; dependency versions are not locked. The exact Xcode version and minimum macOS target remain to be chosen and recorded when scaffolding the native app.

```bash
git clone https://github.com/gmalbert/ai-usage-monitor.git
cd ai-usage-monitor
git switch main
git pull --ff-only
git switch -c codex/macos-menu-bar
python3 --version
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.txt
```

If the repository already exists locally, use that checkout and inspect `git status` before switching branches or pulling. `.venv/` is not currently ignored: keep it out of commits and add an ignore entry during implementation.

Run the provider/normalization tests first. They use mocks and do not need provider credentials:

```bash
python -m unittest tests.test_commandcode tests.test_opencode tests.test_codex tests.test_http tests.test_normalization -v
```

Then try the complete baseline suite on the Mac:

```bash
python -m unittest discover -s tests -v
```

`tests/test_tray.py` imports Tkinter and creates a pystray icon. It may require a graphical session, Tk support, and the macOS pystray backend; record platform failures separately from provider failures. No Mac test outcome is known yet.

For optional live diagnostics after signing in locally:

```bash
python cli.py commandcode
python cli.py opencode --json
python cli.py codex
```

These commands contact providers or start the local Codex app-server and write normalized usage to the local cache. The CLI returns zero even when a provider fails; inspect each JSON provider's `status`, `stale`, and `error`. A selected-provider run can also include other providers previously loaded from cache. Do not treat process success or cached values as proof of live access.

Use the CLI for initial diagnostics. `python app.py --debug` launches the existing Windows-oriented shell and is not the Mac development target.

## Source map

| File | Responsibility / relevance |
| --- | --- |
| `models.py` | Normalized `UsageWindow`, `ProviderUsage`, status values, JSON serialization |
| `usage.py` | Percentages, credits, timestamp parsing, local reset/renewal formatting |
| `providers/commandcode.py` | Authentication file, internal endpoints, organization handling, plan-credit mapping |
| `providers/opencode.py` | OpenCode credential resolution, endpoint, required three-window schema |
| `providers/codex.py` | Executable discovery, app-server messages, limit normalization, local session fallback |
| `providers/http.py` | Sanitized HTTP errors, 10-second timeout, required monitor User-Agent |
| `service.py` | Concurrent refresh, independent failures, cached stale fallback, live minimum |
| `cache.py` | Normalized cache JSON and deserialization |
| `config.py`, `logging_setup.py` | Non-secret settings, data paths, rotating logs |
| `credential_store.py` | Windows Credential Manager implementation; needs a Mac counterpart |
| `ui/tray.py`, `ui/icons.py` | Windows presentation and behavior reference |
| `cli.py` | Diagnostic output and JSON contract |
| `tests/` | Mock-based baseline cases; not complete end-to-end coverage |
| `build_windows.ps1` | Windows-only packaging; preserve it |

## Behavior to carry forward

- Support **three providers**: CommandCode, OpenCode Go, and Codex. The older plan's references to two providers or six meters are incomplete.
- CommandCode and OpenCode each provide 5-hour, weekly, and monthly windows. Codex provides recognized 5-hour/weekly windows and an optional monthly limit when the response includes one. Do not invent missing windows.
- Show remaining percentages, reset/renewal times in local time, credits when available, provider errors, and stale state. Codex can also return an extra-credit balance and available reset credits.
- Default refresh is 300 seconds, with startup and manual refresh. Fetch providers independently and concurrently; one failure must not hide successful results from another.
- The gauge uses the minimum remaining percentage across windows from providers with status `ok`. Exclude stale values. Default thresholds: warning below 50%, critical below 20%; no live values means unavailable/degraded.
- Latest merged changes: monthly remaining percentages appear in compact hover text; renewal countdowns use days and hours. The README's older 5-hour/weekly-only hover description is outdated.
- Compact presentation omits Codex when live refresh fails. Details may show its clearly marked local fallback.
- Preserve cached last-successful values on failure, with their age and a stale label. Never present fallback usage as live.

## Provider and credential contracts

### CommandCode

Current implementation reads `~/.commandcode/auth.json`, field `apiKey` (on Windows it prefers `USERPROFILE`). Sign in normally on the Mac; do not transfer credentials from Windows.

The adapter uses `https://api.commandcode.ai` with `/alpha/whoami`, `/alpha/billing/credits`, `/alpha/billing/subscriptions`, and `/alpha/usage/summary`. Summary requests use the subscription period start as `since` and include `orgId` only when present. Monthly usage comes from `totalMonthlyCredits` against the centralized plan cap. Preserve the `AIUsageMonitor/1.0` User-Agent: the Python adapter includes it to avoid an observed 403.

These are internal, version-sensitive interfaces, not independently reverified for this handoff. Keep endpoint and plan assumptions isolated and fail clearly when the schema changes.

### OpenCode Go

Current resolution order is explicit constructor key, `OPENCODE_GO_API_KEY`, Windows Credential Manager, then existing OpenCode files. On Mac the Windows key lookup returns no key. The existing-file reader checks `~/.config/opencode/auth.json` and `~/.local/share/opencode/auth.json` for top-level `apiKey`, `api_key`, or `token`; it does not support arbitrary nested auth schemas.

The adapter calls `https://opencode.ai/zen/go/v1/usage` and requires `usage.rolling`, `usage.weekly`, and `usage.monthly`, each with `percent` and `resetsAt`. Percent is usage consumed, so remaining is `100 - percent`.

Add a native masked key-entry flow backed by macOS Keychain, including removal. Define and test the credential precedence explicitly. Never put keys in UserDefaults, repository files, cache, logs, command arguments, or diagnostics. Do not assume a Finder-launched app inherits terminal environment variables.

### Codex

Current executable discovery checks `PATH`, then a Windows desktop bundle location. Mac desktop-bundle discovery is **not implemented**. Validate executable discovery and the environment of a GUI-launched app on the target Mac; do not guess a bundled executable path.

Use `providers/codex.py` as the baseline contract for the local app-server exchange and normalization. It owns authentication; the monitor does not read OAuth secrets. Verify protocol compatibility against the installed Mac Codex version before porting. The fallback searches `~/.codex/sessions/**/*.jsonl`, considers the 20 most recently modified files, and extracts saved `rate_limits`; this data is stale. The current implementation does not honor a custom `CODEX_HOME`.

## Mac implementation plan

1. **Establish the baseline.** Run the commands above, record Mac/Python/Xcode versions and failures, and validate any desired live providers without exposing credentials.
2. **Scaffold a native app under `macos/`.** Follow the existing SwiftUI direction, preserve the Python/Windows code, and document the build command and deployment target. Port normalized models and provider adapters into testable Swift services. Use fixture data to make the UI runnable without accounts. Reusing Python through a subprocess is an alternative prototype decision, not an existing architecture; document packaging/environment implications if chosen.
3. **Port provider contracts.** Start with CommandCode and OpenCode, then Codex app-server support. Add fixture tests for valid responses, missing fields, unknown plans, invalid timestamps, absent optional windows, auth/network errors, and stale fallback. Keep secrets and raw session records out of fixtures.
4. **Add the menu-bar UI.** Show all available windows, details, live/stale age, refresh progress, manual refresh, logs, and quit. Use native appearance and accessible status text. UI updates belong on the main actor; serialize/coalesce refreshes.
5. **Add Mac services.** Implement Keychain storage, platform-appropriate cache/log paths, non-secret preferences, wake refresh, launch-at-login, and opt-in notifications. The earlier design proposes `SMAppService` and `UserNotifications`; verify current Apple requirements during implementation.
6. **Validate and document delivery.** Test from Xcode and as a standalone app launched from Finder. Add reproducible build/test instructions. Signing/notarization is a later distribution step, not a prerequisite for this handoff.

Suggested native cache/log locations from the earlier plan are `~/Library/Caches/AIUsageMonitor/cache.json` and `~/Library/Logs/AIUsageMonitor/`. Current Python defaults instead use `~/.cache/AIUsageMonitor` unless `LOCALAPPDATA` or `XDG_CACHE_HOME` is set; settings and cache share that directory. Decide migration behavior explicitly.

## Known implementation issues to avoid carrying over

- Tkinter detail/key dialogs run on worker threads; do not reuse this threading arrangement for native Mac UI.
- Startup toggling always builds a Windows Startup-folder path. It is not a Mac login-item implementation.
- Saved-key writes are Windows-only. There is no Keychain support today.
- Manual and scheduled refreshes can overlap. Cache writes are not atomic and have no refresh coordination.
- Cached data is loaded without immediately marking it stale. Ensure startup cache cannot masquerade as freshly fetched data.
- Threshold notifications trigger for any change into warning/critical, including critical-to-warning recovery, and can use stale windows. The Mac design calls for downward transitions using live data.
- The detail view labels every stale provider as a local Codex record. Use provider-specific stale explanations.
- Codex response reading starts a new stdout reader for each request. Review stream ownership, deadlines, protocol handling, and process cleanup rather than copying this design unchanged.
- Codex local fallback timestamps are set to the current normalization time rather than the original record time. Preserve the real observation age in the Mac implementation.

These are source-review findings, not Mac failures observed in execution. Fix them within the relevant implementation work, with focused tests where warranted.

## Acceptance and next-session prompt

The Mac milestone is ready when the app runs without a terminal, shows all supported providers/windows, distinguishes live and stale data, refreshes at startup/every five minutes/manually/after wake, survives individual provider failures, stores entered keys in Keychain, and supports details, local times, login-item control, and threshold notifications. Test offline/recovery behavior, sleep/wake, missing credentials, Light/Dark appearance, and Finder launch. Keep Windows tests passing and document remaining limits honestly.

Paste this into the next development chat on the Mac:

> Continue the macOS implementation of AI Usage Monitor in this repository. Read AGENTS.md if present and docs/MAC_DEVELOPMENT_HANDOFF.md, then inspect the current source and git status. Preserve the Windows app. Establish the local test baseline, scaffold a native SwiftUI menu-bar app under macos/, and implement provider/model parity with fixture-backed tests. Support CommandCode, OpenCode Go, and Codex, including optional Codex monthly data and clearly stale fallback. Use Keychain for entered secrets and serialize refreshes. Verify current Apple/Codex interfaces before relying on them. Record reproducible Mac build/test commands and any validation limits. Do not commit or push unless requested; any eventual PR must include a detailed Markdown description.
