# CommandCode Usage Monitor Plan

## Goal

Build a small local utility that reads CommandCode usage directly from its internal API and reports:

- 5-hour usage remaining
- Weekly usage remaining
- Monthly subscription-credit usage remaining
- Reset / renewal times
- Optional plan metadata

The implementation should avoid launching or scraping the CommandCode UI.

## Confirmed CommandCode API Behavior

CommandCode 1.36.0 uses:

```text
https://api.commandcode.ai
```

Authentication is performed with the API key stored in:

```text
%USERPROFILE%\.commandcode\auth.json
```

The key is sent as:

```http
Authorization: Bearer <apiKey>
```

The relevant internal endpoints are:

```text
GET /alpha/whoami
GET /alpha/billing/credits
GET /alpha/billing/subscriptions
GET /alpha/usage/summary
```

These are internal / undocumented endpoints, so the integration should isolate API-specific logic so it is easy to update if CommandCode changes them.

## Data Flow

### 1. Load local authentication

Read:

```text
%USERPROFILE%\.commandcode\auth.json
```

Extract only:

```text
apiKey
```

Do not log or display the key.

### 2. Get account identity

Call:

```http
GET https://api.commandcode.ai/alpha/whoami
```

Use the same Bearer token.

If an `org.id` is returned, use it where supported. If `org` is absent or null, omit `orgId` entirely rather than sending an empty value.

### 3. Get rolling usage limits

Call:

```http
GET https://api.commandcode.ai/alpha/billing/credits
```

The important response object is:

```json
{
  "windowLimits": {
    "limited": true,
    "fiveHour": {
      "used": 0,
      "cap": 0,
      "exceeded": false,
      "resetAt": 0
    },
    "weekly": {
      "used": 0,
      "cap": 0,
      "exceeded": false,
      "resetAt": 0
    }
  }
}
```

Compute:

```text
used_percent = used / cap * 100
remaining_percent = 100 - used_percent
remaining_credits = cap - used
```

Convert `resetAt` from Unix milliseconds to local time.

### 4. Get subscription metadata

Call:

```http
GET https://api.commandcode.ai/alpha/billing/subscriptions
```

Use:

```text
data.planId
data.status
data.currentPeriodStart
data.currentPeriodEnd
```

Current confirmed plan:

```text
individual-goat
```

CommandCode 1.36.0 maps that plan to:

```text
70 monthly credits
```

Known plan mappings observed in the client:

```text
individual-go       = 10
individual-provider = 15
individual-pro      = 30
teams-pro           = 40
individual-goat     = 70
individual-pro-v1   = 80
individual-max      = 150
individual-ultra    = 300
```

These mappings should be treated as version-sensitive and kept in one configuration structure.

### 5. Get billing-period usage

Call:

```http
GET https://api.commandcode.ai/alpha/usage/summary
```

Pass the subscription period start as `since`:

```text
?since=<currentPeriodStart>
```

If an organization ID exists, include it as well.

Important fields include:

```text
totalCost
totalCredits
totalMonthlyCredits
totalPurchasedCredits
totalFreeCredits
periodBasis
```

The confirmed response uses:

```text
periodBasis = billing-period
```

Use:

```text
monthly_used = totalMonthlyCredits
monthly_cap = plan monthly credits
monthly_remaining = monthly_cap - monthly_used
monthly_used_percent = monthly_used / monthly_cap * 100
monthly_remaining_percent = 100 - monthly_used_percent
```

The monthly reset / renewal time comes from:

```text
subscription.data.currentPeriodEnd
```

## Normalized Output Model

The program should normalize CommandCode into a simple structure such as:

```json
{
  "provider": "CommandCode",
  "plan": "GOAT",
  "status": "active",
  "five_hour": {
    "used": 0.3813,
    "cap": 14,
    "used_percent": 2.72,
    "remaining_percent": 97.28,
    "reset_at": "2026-08-27T02:18:58-04:00"
  },
  "weekly": {
    "used": 0.3813,
    "cap": 35,
    "used_percent": 1.09,
    "remaining_percent": 98.91,
    "reset_at": "2026-09-02T21:18:58-04:00"
  },
  "monthly": {
    "used": 9.3228,
    "cap": 70,
    "remaining": 60.6772,
    "used_percent": 13.32,
    "remaining_percent": 86.68,
    "reset_at": "2026-09-19T16:15:29-04:00"
  }
}
```

## Initial Implementation

Start with a small Python or PowerShell command-line utility.

Recommended first version:

```text
commandcode-usage
```

Example output:

```text
CommandCode — GOAT

5-hour
  97.28% remaining
  0.38 / 14 credits used
  Resets: Aug 27, 2:18 AM

Weekly
  98.91% remaining
  0.38 / 35 credits used
  Resets: Sep 2, 9:18 PM

Monthly credits
  86.68% remaining
  9.32 / 70 credits used
  60.68 credits remaining
  Renews: Sep 19, 4:15 PM
```

## Architecture

Keep the implementation separated into three layers.

### CommandCode API client

Responsibilities:

- load auth key
- construct authenticated requests
- call CommandCode endpoints
- handle HTTP errors
- handle missing organization IDs
- return raw API data

Suggested module:

```text
providers/commandcode.py
```

### Normalization layer

Responsibilities:

- calculate percentages
- calculate remaining credits
- convert timestamps
- map plan IDs to display names and monthly caps
- return provider-neutral objects

Suggested module:

```text
usage.py
```

### Presentation layer

Responsibilities:

- CLI output
- future tray UI
- future combined CommandCode + OpenCode display

Suggested entry points:

```text
cli.py
tray.py
```

## Error Handling

Handle at least:

- missing `auth.json`
- missing `apiKey`
- expired / invalid API key
- HTTP 401 / 403
- HTTP 429
- missing or null organization
- missing `windowLimits`
- missing subscription
- unknown plan ID
- zero usage cap
- malformed timestamp
- network timeout
- CommandCode changing endpoint paths or response fields

Never print the API key in errors or logs.

## Refresh Strategy

For an interactive monitor:

```text
refresh every 5 minutes
```

There is little value in polling more frequently for quota display.

Allow manual refresh as well.

Cache the last successful result so temporary API failures do not blank the UI.


## OpenCode Go Provider Plan

OpenCode Go is now confirmed to expose exactly the three usage windows needed for the monitor.

### Confirmed endpoint

```text
GET https://opencode.ai/zen/go/v1/usage
```

Authentication:

```http
Authorization: Bearer <OpenCode Go API key>
```

### Confirmed live response schema

The live endpoint returns:

```json
{
  "usage": {
    "rolling": {
      "status": "ok",
      "percent": 0,
      "resetsAt": "2026-08-27T07:00:13.095Z"
    },
    "weekly": {
      "status": "ok",
      "percent": 1,
      "resetsAt": "2026-08-31T00:00:00.095Z"
    },
    "monthly": {
      "status": "ok",
      "percent": 14,
      "resetsAt": "2026-09-23T00:22:31.095Z"
    }
  }
}
```

Interpretation:

```text
rolling  = 5-hour window
weekly   = weekly window
monthly  = monthly window
```

The API already returns the percentage used, so:

```text
remaining_percent = 100 - percent
```

No separate cap/used-credit calculation is necessary unless OpenCode later exposes those fields.

### Confirmed current example

For the sample response above:

```text
5-hour remaining  = 100%
Weekly remaining  = 99%
Monthly remaining = 86%
```

Reset timestamps are ISO-8601 UTC values and should be converted to local Windows time for display.

### Credential discovery

Use the user's existing OpenCode Go credential whenever possible.

Preferred resolution order:

1. explicit environment variable override
2. OpenCode's existing local credential store
3. configuration error with clear instructions

Recommended environment override:

```text
OPENCODE_GO_API_KEY
```

Do not duplicate the key into a new plaintext config file unless the user explicitly chooses to.

The monitor should never:

```text
print the API key
log the Authorization header
write the key to debug output
include the key in crash reports
```

### OpenCode API client

Suggested module:

```text
providers/opencode.py
```

Responsibilities:

- resolve the OpenCode Go API key
- call `/zen/go/v1/usage`
- validate that `usage.rolling`, `usage.weekly`, and `usage.monthly` exist
- normalize percentages
- convert `resetsAt` timestamps
- distinguish authentication errors, endpoint errors, and schema changes
- return a provider-neutral `ProviderUsage` object

Suggested normalized structure:

```json
{
  "provider": "OpenCode Go",
  "plan": "Go",
  "status": "active",
  "five_hour": {
    "used_percent": 0,
    "remaining_percent": 100,
    "reset_at": "2026-08-27T03:00:13-04:00"
  },
  "weekly": {
    "used_percent": 1,
    "remaining_percent": 99,
    "reset_at": "2026-08-30T20:00:00-04:00"
  },
  "monthly": {
    "used_percent": 14,
    "remaining_percent": 86,
    "reset_at": "2026-09-22T20:22:31-04:00"
  }
}
```

### OpenCode validation

On every successful response:

```text
assert response contains usage
assert usage contains rolling
assert usage contains weekly
assert usage contains monthly
assert each window contains percent
assert each window contains resetsAt
```

If any required field is missing, do not guess.

Return:

```text
OpenCode Go usage API format changed. Provider adapter needs updating.
```

### OpenCode error handling

Handle:

```text
missing API key
401 authentication failure
403 authorization failure
404 endpoint unavailable
429 API rate limit
network timeout
DNS failure
TLS failure
missing rolling window
missing weekly window
missing monthly window
invalid percent value
invalid reset timestamp
unexpected response schema
```

One provider failing must not take down the combined monitor.

### OpenCode polling

Recommended default:

```text
refresh every 5 minutes
```

This matches the CommandCode refresh cadence and keeps the application simple.

Also support:

```text
manual refresh
last successful value cache
stale-data indicator
last-updated timestamp
```

### OpenCode standalone diagnostic mode

Before the tray app is built, support:

```text
usage-monitor opencode
```

Example:

```text
OpenCode Go

5-hour
  100.0% remaining
  Resets: Aug 27, 3:00 AM

Weekly
  99.0% remaining
  Resets: Aug 30, 8:00 PM

Monthly
  86.0% remaining
  Resets: Sep 22, 8:22 PM
```

Machine-readable mode:

```text
usage-monitor opencode --json
```

### OpenCode success criteria

OpenCode support is complete when the app can obtain, without browser scraping:

```text
5-hour percent remaining
weekly percent remaining
monthly percent remaining
reset time for each window
```

and those values match OpenCode's own usage display.



## Codex Provider Plan

Codex should be supported as a third provider alongside CommandCode and OpenCode Go.

The preferred integration is **not** to scrape the Codex UI. Current Codex releases expose structured account usage through `codex app-server`, which is the local JSON-RPC interface used by Codex clients.

### Preferred integration: `codex app-server`

Start the local Codex app server:

```text
codex app-server
```

By default, it communicates over stdin/stdout using newline-delimited JSON.

The usage monitor should launch a short-lived `codex app-server` child process when refreshing Codex data, initialize it, issue the rate-limit request, parse the response, and then terminate the process.

This has several advantages:

```text
uses Codex's own existing login/authentication
does not require copying OAuth tokens
does not require browser scraping
does not require reverse-engineering ChatGPT cookies
uses the same structured data Codex itself consumes
works on Windows and macOS
keeps token refresh logic inside Codex
```

### Primary Codex request

After initializing the app-server connection, call:

```json
{
  "method": "account/rateLimits/read",
  "id": 1
}
```

The response contains structured ChatGPT/Codex limits.

Conceptually:

```json
{
  "id": 1,
  "result": {
    "rateLimits": {
      "primary": {
        "usedPercent": 25,
        "windowDurationMins": 300,
        "resetsAt": 1730947200
      },
      "secondary": {
        "usedPercent": 5,
        "windowDurationMins": 10080,
        "resetsAt": 1731547200
      },
      "rateLimitReachedType": null
    },
    "rateLimitResetCredits": {
      "availableCount": 0
    }
  }
}
```

The exact fields should be validated against the installed Codex version because Codex evolves quickly.

### Window interpretation

Do not blindly assume `primary` and `secondary` names.

Use:

```text
windowDurationMins
```

to classify the windows.

Typical values:

```text
300 minutes    → 5-hour window
10080 minutes  → 7-day / weekly window
```

Mapping logic:

```python
if 270 <= window_minutes <= 330:
    window_name = "5-hour"
elif 9000 <= window_minutes <= 11000:
    window_name = "weekly"
else:
    window_name = f"{window_minutes}-minute"
```

This is safer than depending solely on `primary` / `secondary`.

### Codex percentage calculation

Codex reports:

```text
usedPercent
```

Therefore:

```text
remaining_percent = 100 - usedPercent
```

Example:

```text
usedPercent = 25
remainingPercent = 75
```

### Reset timestamps

Codex `resetsAt` values are Unix timestamps in seconds.

Convert them to timezone-aware local dates before display.

Example Python:

```python
from datetime import datetime, timezone

reset = datetime.fromtimestamp(
    resets_at,
    tz=timezone.utc,
).astimezone()
```

### Monthly / credit-limit data

Codex's `account/rateLimits/read` response can also expose an effective monthly credit limit through spend-control / individual-limit data when the account or workspace provides one.

Treat this as optional.

Possible normalized fields:

```text
monthly credit limit
monthly credits used
monthly credits remaining
monthly used percent
monthly remaining percent
monthly reset
```

If no monthly individual limit is returned:

```text
monthly = null
```

Do not manufacture a monthly meter.

For personal ChatGPT plans, the useful Codex display may therefore be:

```text
5-hour
weekly
credit balance
```

rather than forcing the same three-window structure used by OpenCode Go.

### Codex credit balance

When returned by the Codex rate-limit response, also expose:

```text
credits.balance
```

This is especially useful when purchased flexible-usage credits are available.

Display separately from included plan rate limits:

```text
Codex — Plus

5-hour   78% remaining
Weekly   91% remaining

Extra credits
$12.40 remaining
```

Do not combine purchased credits with the 5-hour or weekly percentages.

### Earned rate-limit resets

Codex may return:

```text
rateLimitResetCredits.availableCount
```

Optionally show:

```text
Resets available: 1
```

The monitor should display this information only.

It should **not** automatically redeem a reset.

Any future reset-redemption feature must require an explicit user action and confirmation.

### Optional Codex usage-history request

Codex app-server also exposes:

```text
account/usage/read
```

This can be used later for usage-history or analytics views.

Potential future detail screen:

```text
today's activity
7-day activity
daily token history
```

This is optional for the first release.

The initial Codex integration should focus on:

```text
current rate limits
reset times
credit balance when available
monthly limit when available
earned reset count when available
```

### Authentication

The monitor should not directly manage Codex OAuth credentials.

Codex itself should own authentication.

User setup:

```text
codex login
```

or use the existing Codex sign-in.

Verification:

```text
codex login status
```

The monitor then communicates with `codex app-server`, allowing Codex to use and refresh its own stored credentials.

This is preferable to reading and replaying OAuth access/refresh tokens from:

```text
~/.codex/auth.json
```

### App-server lifecycle

Recommended refresh flow:

```text
1. start `codex app-server --stdio`
2. send initialize request
3. wait for initialization response
4. send account/rateLimits/read
5. parse response
6. optionally send account/usage/read
7. terminate app-server
```

For a five-minute refresh cadence, a short-lived process is simple and robust.

If startup overhead becomes noticeable, a later version can keep one app-server process alive and reuse it.

### Initialization

The tray/menu app should identify itself using a client name such as:

```text
AIUsageMonitor
```

The implementation should follow the JSON-RPC initialization schema generated by the installed Codex version.

Codex can generate matching schemas with:

```text
codex app-server generate-json-schema --out <directory>
```

or:

```text
codex app-server generate-ts --out <directory>
```

This makes it possible to validate compatibility against the exact installed Codex release.

### Python implementation

Suggested module:

```text
providers/codex.py
```

Responsibilities:

```text
locate codex executable
launch codex app-server
perform JSON-RPC initialization
request account/rateLimits/read
classify windows by duration
calculate remaining percentages
convert reset timestamps
read optional credit/monthly data
return normalized ProviderUsage
cleanly terminate child process
```

Recommended process API:

```python
subprocess.Popen(
    ["codex", "app-server", "--stdio"],
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    bufsize=1,
)
```

### macOS Swift implementation

For the native macOS menu-bar app, there are two practical approaches.

#### Option A — launch Codex app-server

Use `Process` and `Pipe`:

```swift
let process = Process()
process.executableURL = URL(fileURLWithPath: codexPath)
process.arguments = ["app-server", "--stdio"]
```

Then exchange newline-delimited JSON through stdin/stdout.

This keeps Codex authentication inside Codex and mirrors the Windows implementation.

#### Option B — small local helper

If maintaining JSON-RPC framing in Swift becomes inconvenient, ship a tiny helper executable that outputs normalized Codex usage JSON.

Example:

```text
codex-usage-helper --json
```

The Swift menu-bar app reads that output.

Option A is preferable unless implementation complexity becomes excessive.

### Codex normalized model

Example:

```json
{
  "provider": "Codex",
  "plan": "Plus",
  "status": "active",
  "five_hour": {
    "used_percent": 22,
    "remaining_percent": 78,
    "reset_at": "..."
  },
  "weekly": {
    "used_percent": 9,
    "remaining_percent": 91,
    "reset_at": "..."
  },
  "monthly": null,
  "credit_balance": 12.40,
  "reset_credits_available": 1
}
```

If a monthly limit is provided:

```json
{
  "monthly": {
    "used_percent": 32,
    "remaining_percent": 68,
    "used": 8,
    "cap": 25,
    "remaining": 17,
    "reset_at": "..."
  }
}
```

### Local rollout-log fallback

Codex writes structured rate-limit snapshots into its local session/rollout JSONL data.

Those records can include:

```text
rate_limits
used_percent
window_minutes
resets_at
plan_type
token usage
```

This provides a useful fallback if app-server access breaks.

Advantages:

```text
no network request from the monitor
no credential access
structured local data
```

Disadvantages:

```text
may be stale until Codex has recently run
requires finding newest rollout record
schema may change
does not guarantee a fresh server-side value
```

Therefore:

```text
app-server       = preferred
local rollout log = fallback
```

The UI must clearly mark fallback values as potentially stale.

### Direct ChatGPT backend endpoint — diagnostic fallback only

Current Codex internals ultimately retrieve usage from the ChatGPT backend.

A backend route used by Codex clients has appeared as:

```text
https://chatgpt.com/backend-api/codex/usage
```

It uses Codex-managed ChatGPT OAuth authentication and account context.

Do **not** make this the default monitor integration.

Reasons:

```text
internal endpoint
undocumented stability guarantees
OAuth token handling becomes the monitor's responsibility
account headers may be required
token refresh logic may change
```

Keep this only as a diagnostic / reverse-engineering fallback if the app-server approach ever stops exposing the necessary data.

### Stable manual fallback

Always keep a user-visible fallback:

```text
Codex CLI: /status
```

and:

```text
ChatGPT / Codex Settings → Usage
```

The tray/menu detail view can include:

```text
Open Codex Usage Dashboard
```

for manual verification.

### Error handling

Codex provider statuses should include:

```text
CODEX_NOT_INSTALLED
NOT_LOGGED_IN
APP_SERVER_START_FAILED
APP_SERVER_PROTOCOL_ERROR
RATE_LIMIT_DATA_UNAVAILABLE
NETWORK_ERROR
SCHEMA_ERROR
STALE_LOG_FALLBACK
OK
```

Example UI:

```text
Codex
Not signed in — run `codex login`
```

or:

```text
Codex
Usage temporarily unavailable
Last known: 78% / 91%
```

### Refresh strategy

Use the same default refresh interval:

```text
5 minutes
```

The Codex provider refresh runs concurrently with:

```text
CommandCodeProvider
OpenCodeGoProvider
CodexProvider
```

A failure must not delay the other two.

### Combined three-provider display

The compact display should become:

```text
AI Usage

CommandCode — GOAT
5h        97.3% remaining
Weekly    98.9% remaining
Monthly   86.7% remaining

OpenCode Go
5h       100.0% remaining
Weekly    99.0% remaining
Monthly   86.0% remaining

Codex — Plus
5h        78.0% remaining
Weekly    91.0% remaining
Credits   $12.40
```

If Codex supplies an effective monthly limit, add:

```text
Monthly   68.0% remaining
```

### Windows tray integration

Add Codex to the tray menu:

```text
CommandCode — GOAT
  5h: 97.3%
  Week: 98.9%
  Month: 86.7%

OpenCode Go
  5h: 100.0%
  Week: 99.0%
  Month: 86.0%

Codex — Plus
  5h: 78.0%
  Week: 91.0%
  Credits: $12.40
```

The tray's aggregate warning state should include all available Codex percentage windows.

Do not include a dollar credit balance in the minimum-percentage calculation.

### macOS menu bar integration

Add Codex to the same menu-bar popover:

```text
Codex — Plus
5-hour       78.0%
Weekly       91.0%
Credits      $12.40
```

The macOS aggregate menu-bar percentage should include Codex percentage windows just like Windows.

### Codex implementation order

1. Verify `codex` executable is installed.
2. Verify `codex login status`.
3. Start `codex app-server --stdio`.
4. Implement JSON-RPC initialization.
5. Call `account/rateLimits/read`.
6. Capture the live response from the user's account.
7. Map primary/secondary windows by duration.
8. Add reset-time conversion.
9. Add optional credit balance.
10. Add optional monthly individual limit.
11. Add earned reset-count display.
12. Normalize into `ProviderUsage`.
13. Add `usage-monitor codex`.
14. Add `usage-monitor codex --json`.
15. Add rollout-log fallback.
16. Add Windows tray integration.
17. Add macOS menu-bar integration.
18. Add usage-dashboard shortcut.
19. Add compatibility tests across Codex updates.

### Codex success criteria

Codex support is complete when the application can, without scraping a browser:

```text
show current 5-hour usage remaining
show current weekly usage remaining
show reset times
show purchased/flexible credit balance when returned
show monthly credit limit when returned
show available earned resets when returned
continue working if CommandCode or OpenCode fail
work from both Windows tray and macOS menu bar
```


## Combined CommandCode + OpenCode + Codex Monitor

Once all provider adapters are individually proven, combine them behind the common usage model.

Normalize both providers to similar fields:

```text
provider
plan
window name
used
cap
used percentage
remaining percentage
reset time
```

The final display could look like:

```text
CommandCode — GOAT
5h        97.3% remaining
Weekly    98.9% remaining
Monthly   86.7% remaining

OpenCode Go
5h        ...
Weekly    ...
Monthly   ...
```

Provider-specific differences should remain inside each provider adapter.

## Windows Tray Application — Implementation Guide

The first production UI should be a small Windows system-tray application that runs quietly in the background and displays both CommandCode and OpenCode Go usage.

### Recommended implementation stack

Use Python for the first implementation.

Recommended packages:

```text
pystray
Pillow
requests
python-dateutil
```

Optional:

```text
platformdirs
```

Why this stack:

- Python is already suitable for the API and normalization work.
- `pystray` provides a straightforward Windows notification-area icon.
- `Pillow` can generate tray icons dynamically.
- `requests` keeps HTTP code simple.
- `python-dateutil` helps with ISO timestamps.
- The finished app can be packaged into a single `.exe` with PyInstaller.

Install:

```powershell
py -m pip install pystray pillow requests python-dateutil platformdirs
```

Packaging later:

```powershell
py -m pip install pyinstaller
```

### Recommended repository layout

```text
ai-usage-monitor/
│
├── app.py
├── cli.py
├── config.py
├── models.py
├── cache.py
├── logging_setup.py
│
├── providers/
│   ├── __init__.py
│   ├── commandcode.py
│   └── opencode.py
│
├── ui/
│   ├── __init__.py
│   ├── tray.py
│   ├── menu.py
│   └── icons.py
│
├── tests/
│   ├── test_commandcode.py
│   ├── test_opencode.py
│   └── test_normalization.py
│
├── requirements.txt
└── README.md
```

### Core data model

Keep the UI independent from provider-specific API structures.

Example:

```python
from dataclasses import dataclass
from datetime import datetime
from typing import Optional

@dataclass
class UsageWindow:
    name: str
    used_percent: float
    remaining_percent: float
    reset_at: Optional[datetime] = None
    used: Optional[float] = None
    cap: Optional[float] = None
    remaining: Optional[float] = None
    source_type: str = "usage_window"

@dataclass
class ProviderUsage:
    provider: str
    plan: Optional[str]
    status: str
    five_hour: Optional[UsageWindow]
    weekly: Optional[UsageWindow]
    monthly: Optional[UsageWindow]
    fetched_at: datetime
    stale: bool = False
    error: Optional[str] = None
```

### Provider interface

Use a simple interface:

```python
class UsageProvider:
    def fetch(self) -> ProviderUsage:
        raise NotImplementedError
```

Implement:

```text
CommandCodeProvider
OpenCodeGoProvider
CodexProvider
```

The tray UI should know nothing about `/alpha/...`, `/zen/go/...`, auth-file formats, or provider-specific response fields.

### CommandCode provider implementation

Use the confirmed flow:

```text
%USERPROFILE%\.commandcode\auth.json
        ↓
apiKey
        ↓
Authorization: Bearer <apiKey>
        ↓
https://api.commandcode.ai
```

Calls:

```text
GET /alpha/whoami
GET /alpha/billing/credits
GET /alpha/billing/subscriptions
GET /alpha/usage/summary
```

Important logic:

```text
If whoami.org.id is null:
    omit orgId entirely

Do not send:
    ?orgId=
```

Use:

```text
credits.windowLimits.fiveHour
credits.windowLimits.weekly
subscription.data.planId
subscription.data.currentPeriodStart
subscription.data.currentPeriodEnd
summary.totalMonthlyCredits
summary.periodBasis
```

Monthly cap comes from the plan mapping.

Current observed mappings:

```python
COMMANDCODE_PLAN_CREDITS = {
    "individual-go": 10,
    "individual-provider": 15,
    "individual-pro": 30,
    "teams-pro": 40,
    "individual-goat": 70,
    "individual-pro-v1": 80,
    "individual-max": 150,
    "individual-ultra": 300,
}
```

Keep this dictionary isolated so changes are easy to update.

### OpenCode Go provider implementation

Use:

```text
GET https://opencode.ai/zen/go/v1/usage
Authorization: Bearer <Go API key>
```

Read:

```text
usage.rolling.percent
usage.rolling.resetsAt

usage.weekly.percent
usage.weekly.resetsAt

usage.monthly.percent
usage.monthly.resetsAt
```

Compute:

```text
remaining = 100 - percent
```

### Concurrent refresh

Do not fetch providers sequentially on the UI thread.

Use a worker thread or `concurrent.futures.ThreadPoolExecutor`.

Example approach:

```python
with ThreadPoolExecutor(max_workers=2) as pool:
    futures = {
        "commandcode": pool.submit(commandcode.fetch),
        "opencode": pool.submit(opencode.fetch),
    }
```

Then update cached state when each returns.

The tray thread must remain responsive while network requests occur.

### Refresh cadence

Default:

```text
5 minutes
```

Recommended constant:

```python
REFRESH_SECONDS = 300
```

Allow configuration later.

Refresh immediately at application startup, then every 300 seconds.

Also include a manual tray-menu item:

```text
Refresh now
```

### HTTP timeout

Never allow an API request to hang indefinitely.

Recommended:

```python
HTTP_TIMEOUT_SECONDS = 10
```

Use:

```python
requests.get(url, headers=headers, timeout=10)
```

### Cache design

Store the last successful normalized result for each provider in memory.

Optional disk cache:

```text
%LOCALAPPDATA%\AIUsageMonitor\cache.json
```

Use disk cache only for usage values and timestamps.

Never cache API keys.

Cache structure:

```json
{
  "commandcode": {
    "...": "..."
  },
  "opencode": {
    "...": "..."
  },
  "saved_at": "..."
}
```

On temporary API failure:

```text
show last known values
mark provider stale
show last successful update time
```

### Tray icon behavior

The tray icon should communicate the most constrained quota.

Determine:

```text
minimum remaining percentage across all active windows/providers
```

Example:

```text
CommandCode 5h      97%
CommandCode weekly  99%
CommandCode monthly 87%
OpenCode 5h        100%
OpenCode weekly     99%
OpenCode monthly    86%

minimum = 86%
```

Use that value for the tray status.

Suggested states:

```text
>= 50% remaining    normal
20–49% remaining    warning
< 20% remaining     critical
provider error      degraded
```

Do not hard-code colors into provider logic; color is a UI concern.

### Tray tooltip

Keep it concise because Windows tooltip space is limited.

Example:

```text
AI Usage
CC: 97% / 99% / 87%
OC: 100% / 99% / 86%
```

Or:

```text
AI Usage — lowest 86% remaining
```

### Tray menu

Recommended menu:

```text
AI Usage Monitor
-------------------------
CommandCode — GOAT
  5h: 97.3%
  Week: 98.9%
  Month: 86.7%

OpenCode Go
  5h: 100.0%
  Week: 99.0%
  Month: 86.0%

Last updated: 9:42 PM
-------------------------
Refresh now
Open detailed view
Start with Windows   [check]
Open logs
Exit
```

`pystray` menus are not ideal for rich formatting, so use a separate detail window for the full view.

### Detailed view

Use either:

```text
tkinter
```

or a small local web UI.

For the first version, use `tkinter` because it is bundled with normal Python distributions and adds no external runtime dependency.

Recommended detail layout:

```text
AI Usage Monitor

CommandCode — GOAT
5-hour   [██████████████████░░] 97.3% remaining
          resets Aug 27, 2:19 AM

Weekly   [███████████████████░] 98.9% remaining
          resets Sep 2, 9:19 PM

Monthly  [█████████████████░░░] 86.7% remaining
          60.68 credits left
          renews Sep 19, 4:15 PM


OpenCode Go
5-hour   [████████████████████] 100.0% remaining
          resets Aug 27, 3:00 AM

Weekly   [███████████████████░] 99.0% remaining
          resets Aug 30, 8:00 PM

Monthly  [█████████████████░░░] 86.0% remaining
          resets Sep 22, 8:22 PM
```

### Reset-time formatting

Always store times internally as timezone-aware `datetime` objects.

Display in Windows local time.

Useful formats:

```text
Aug 27, 3:00 AM
Sep 22, 8:22 PM
```

Optional relative form:

```text
resets in 5h 18m
```

Best UI:

```text
Aug 27, 3:00 AM · in 5h 18m
```

### Startup behavior

The app should:

1. launch
2. load cached values
3. show tray icon immediately
4. start provider refresh in background
5. replace cached values when live calls complete
6. schedule the next refresh

Do not block application startup waiting for API calls.

### Start with Windows

Simplest implementation:

Create a shortcut in:

```text
%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup
```

The tray menu can expose:

```text
Start with Windows
```

When enabled:

```text
create shortcut to packaged EXE
```

When disabled:

```text
delete shortcut
```

Alternative:

```text
HKCU\Software\Microsoft\Windows\CurrentVersion\Run
```

The Startup-folder shortcut is easier to inspect and remove manually.

### Logging

Log to:

```text
%LOCALAPPDATA%\AIUsageMonitor\logs\usage-monitor.log
```

Use rotating logs.

Suggested Python setup:

```python
logging.handlers.RotatingFileHandler(
    path,
    maxBytes=1_000_000,
    backupCount=3,
)
```

Log:

```text
startup
provider refresh success
provider refresh failure
HTTP status code
schema validation failure
cache load/save
manual refresh
application exit
```

Never log:

```text
Authorization headers
API keys
auth.json contents
raw responses containing credentials
```

### Configuration

Use:

```text
%LOCALAPPDATA%\AIUsageMonitor\config.json
```

Suggested fields:

```json
{
  "refresh_seconds": 300,
  "warning_threshold": 50,
  "critical_threshold": 20,
  "start_with_windows": true,
  "show_notifications": true
}
```

Do not store provider API keys there.

### Notifications

Optional but useful.

Trigger only on threshold transitions, not every refresh.

Examples:

```text
OpenCode monthly usage below 20% remaining
CommandCode weekly usage below 20% remaining
```

Avoid repeated notifications.

Maintain previous threshold state:

```text
normal
warning
critical
```

Notify only when moving downward into a new state.

### Packaging with PyInstaller

Once the Python app is stable:

```powershell
pyinstaller `
  --noconsole `
  --onefile `
  --name AIUsageMonitor `
  app.py
```

For a custom icon later:

```powershell
pyinstaller `
  --noconsole `
  --onefile `
  --name AIUsageMonitor `
  --icon assets\usage.ico `
  app.py
```

Output:

```text
dist\AIUsageMonitor.exe
```

`--noconsole` prevents an unwanted terminal window from appearing with the tray app.

During development, omit `--noconsole` so exceptions remain visible.

### Development mode

Provide:

```powershell
py app.py --debug
```

Debug mode should:

```text
enable console logging
reduce refresh interval optionally
show detailed errors
never reveal auth secrets
```

### CLI mode

Keep the CLI even after the tray app exists.

Examples:

```text
usage-monitor
usage-monitor commandcode
usage-monitor opencode
usage-monitor --json
usage-monitor --refresh
```

This provides an easy diagnostic path if the tray UI fails.

### Health/status model

Each provider should independently report:

```text
OK
STALE
AUTH_ERROR
NETWORK_ERROR
SCHEMA_ERROR
API_ERROR
```

Example:

```python
class ProviderStatus(Enum):
    OK = "ok"
    STALE = "stale"
    AUTH_ERROR = "auth_error"
    NETWORK_ERROR = "network_error"
    SCHEMA_ERROR = "schema_error"
    API_ERROR = "api_error"
```

### Graceful degradation

If CommandCode fails:

```text
CommandCode: unavailable
OpenCode: 100 / 99 / 86
```

If OpenCode fails:

```text
CommandCode: 97 / 99 / 87
OpenCode: unavailable
```

If both fail:

```text
AI Usage Monitor
Last successful update: <time>
Both providers currently unavailable
```

Never exit just because a provider request fails.

### Testing

At minimum, write fixture-based tests for:

```text
CommandCode credits response
CommandCode subscription response
CommandCode summary response
CommandCode account with orgId
CommandCode account without orgId
OpenCode usage response
missing OpenCode monthly field
401 responses
429 responses
malformed timestamps
zero CommandCode cap
unknown CommandCode plan
```

Do not make live API calls in normal unit tests.

### Version-sensitive constants

Keep all private/internal API assumptions centralized.

Example:

```python
COMMANDCODE_BASE_URL = "https://api.commandcode.ai"
COMMANDCODE_CREDITS_PATH = "/alpha/billing/credits"
COMMANDCODE_SUBSCRIPTIONS_PATH = "/alpha/billing/subscriptions"
COMMANDCODE_SUMMARY_PATH = "/alpha/usage/summary"

OPENCODE_USAGE_URL = "https://opencode.ai/zen/go/v1/usage"
```

If an API changes, only the provider adapter should require modification.

### Recommended implementation sequence

Build in this order:

1. Create project skeleton.
2. Implement normalized data classes.
3. Implement CommandCode provider.
4. Implement OpenCode Go provider.
5. Add unit tests using saved sample responses.
6. Build CLI output.
7. Add JSON CLI output.
8. Add in-memory cache.
9. Add concurrent refresh.
10. Add tray icon.
11. Add tray menu.
12. Add detailed `tkinter` view.
13. Add rotating logs.
14. Add Start-with-Windows toggle.
15. Add threshold notifications.
16. Add persistent non-secret config.
17. Package with PyInstaller.
18. Test packaged EXE on a clean Windows login.
19. Verify startup shortcut behavior.
20. Add README troubleshooting instructions.

### Windows tray app success criteria

The tray version is complete when:

```text
it launches without a console window
it reads existing provider credentials automatically
it displays all six usage windows
it refreshes every 5 minutes
manual refresh works
one provider can fail without affecting the other
reset times display in local time
no API secrets are written to logs/config
it can start automatically with Windows
it can be packaged as one EXE
```


## Security

The monitor should:

- read the existing CommandCode API key only at runtime
- never copy the key into source code
- never save the key in another config file
- never log request headers
- never display the key
- avoid sending CommandCode usage data anywhere except the local application

## Maintenance Risk

The CommandCode endpoints discovered here are internal and currently use the `/alpha/` namespace.

Therefore:

- endpoint paths may change
- response schemas may change
- auth behavior may change
- plan IDs / credit amounts may change

Keep these values centralized so future fixes are small.

A useful compatibility check at startup should validate that:

```text
/alpha/billing/credits
```

still returns a `windowLimits` object.

If not, surface a clear message such as:

```text
CommandCode API format changed. Provider adapter needs updating.
```

## Recommended Build Order

1. Create a standalone CommandCode API client.
2. Reproduce the current 5-hour and weekly values.
3. Add subscription lookup.
4. Add monthly billing-period usage.
5. Normalize all three meters.
6. Add human-readable CLI output.
7. Add JSON output for reuse by other tools.
8. Add OpenCode provider support.
9. Add caching and resilient error handling.
10. Build the Windows tray interface.
11. Optionally add notifications for low remaining usage.


## Confirmed Live Usage Snapshot

The implementation has been validated against live API responses from both providers.

### CommandCode

Confirmed data sources:

```text
5-hour   → credits.windowLimits.fiveHour
Weekly   → credits.windowLimits.weekly
Monthly  → summary.totalMonthlyCredits vs plan monthly credit cap
```

Confirmed current plan:

```text
individual-goat
monthly cap = 70 credits
```

Confirmed authentication:

```text
%USERPROFILE%\.commandcode\auth.json
Authorization: Bearer <apiKey>
```

### OpenCode Go

Confirmed live endpoint:

```text
GET https://opencode.ai/zen/go/v1/usage
```

Confirmed response fields:

```text
usage.rolling.percent
usage.rolling.resetsAt
usage.weekly.percent
usage.weekly.resetsAt
usage.monthly.percent
usage.monthly.resetsAt
```

Confirmed calculation:

```text
remaining_percent = 100 - percent
```

This means the data layer for all six meters has been proven before tray-app implementation begins.

## Success Criteria

The first milestone is complete when one command can return:

```text
CommandCode plan
5-hour used / remaining / reset
Weekly used / remaining / reset
Monthly used / remaining / renewal
```

without launching CommandCode itself and without exposing the stored API key.

The final milestone is a cross-platform utility: a Windows system-tray app and a macOS menu-bar app that show both CommandCode and OpenCode usage in one place.

## macOS Menu Bar Application — Implementation Guide

The macOS version should be a first-class companion to the Windows tray app and should expose the same CommandCode and OpenCode Go data through a native menu-bar experience.

### Recommended implementation

Prefer a native SwiftUI app for the production macOS version:

```text
Swift
SwiftUI
MenuBarExtra
URLSession
SMAppService
UserNotifications
```

A Python + `rumps` prototype is acceptable for rapid delivery, but the native SwiftUI implementation is the preferred long-term path because it provides better menu-bar behavior, lower overhead, native launch-at-login support, native notifications, and easier signed/notarized distribution.

### Shared architecture

Keep the provider/data model conceptually identical across Windows and macOS:

```text
CommandCodeProvider ─┐
                     ├─> normalized ProviderUsage ─> cache/refresh service ─> platform UI
OpenCodeGoProvider ──┘
```

Only the shell should differ:

```text
Windows → system tray
macOS   → menu bar
```

The provider logic must continue to expose:

```text
CommandCode
  5-hour
  weekly
  monthly billing-period credits

OpenCode Go
  rolling / 5-hour
  weekly
  monthly
```

### macOS credentials

CommandCode:

```text
~/.commandcode/auth.json
```

Read `apiKey` and send:

```http
Authorization: Bearer <apiKey>
```

OpenCode Go credential resolution order:

```text
OPENCODE_GO_API_KEY
    ↓
existing OpenCode credential store
    ↓
configuration error
```

Never copy either credential into a second plaintext config file, logs, crash output, or UI diagnostics.

### Menu bar status item

The menu bar item should show the lowest remaining percentage across all active windows.

Example:

```text
AI 86%
```

Determine:

```text
minimum remaining percentage across:
  CommandCode 5h
  CommandCode weekly
  CommandCode monthly
  OpenCode 5h
  OpenCode weekly
  OpenCode monthly
```

Suggested states:

```text
>= 50% remaining    normal
20–49% remaining    warning
< 20% remaining     critical
provider error      degraded
```

Because menu bar rendering varies across Light/Dark modes, do not rely on color alone. Include text and optionally a warning glyph:

```text
AI 86%
AI 31%
AI ⚠ 14%
```

### SwiftUI MenuBarExtra

Use `MenuBarExtra` for the primary macOS UI.

Conceptual structure:

```swift
MenuBarExtra("AI Usage", systemImage: "gauge.with.dots.needle.50percent") {
    MenuBarView()
}
.menuBarExtraStyle(.window)
```

`.window` style is recommended because the app needs richer content than a simple command menu.

### Menu content

Recommended compact view:

```text
AI Usage Monitor
────────────────────────────

CommandCode — GOAT
5-hour        97.3%
Weekly        98.9%
Monthly       86.7%

OpenCode Go
5-hour       100.0%
Weekly        99.0%
Monthly       86.0%

Updated 2:54 PM

────────────────────────────
Refresh Now
Show Details
Open Logs
Launch at Login  ✓
Quit
```

### Detailed view

The richer detail window/popover should show percentages, absolute credits when available, and reset/renewal times.

Example:

```text
CommandCode — GOAT

5-hour
97.3% remaining
0.38 / 14 credits used
Resets Aug 27, 2:19 AM

Weekly
98.9% remaining
0.38 / 35 credits used
Resets Sep 2, 9:19 PM

Monthly
86.7% remaining
60.68 credits left
Renews Sep 19, 4:15 PM

OpenCode Go

5-hour
100.0% remaining
Resets Aug 27, 3:00 AM

Weekly
99.0% remaining
Resets Aug 30, 8:00 PM

Monthly
86.0% remaining
Resets Sep 22, 8:22 PM
```

### SwiftUI data model

Suggested types:

```swift
struct UsageWindow: Identifiable {
    let id = UUID()
    let name: String
    let usedPercent: Double
    let remainingPercent: Double
    let resetAt: Date?
    let used: Double?
    let cap: Double?
    let remaining: Double?
    let sourceType: UsageSourceType
}

struct ProviderUsage {
    let provider: String
    let plan: String?
    let status: ProviderStatus
    let fiveHour: UsageWindow?
    let weekly: UsageWindow?
    let monthly: UsageWindow?
    let fetchedAt: Date
    let stale: Bool
    let error: String?
}
```

Provider protocol:

```swift
protocol UsageProvider {
    func fetch() async throws -> ProviderUsage
}
```

Implement:

```text
CommandCodeProvider
OpenCodeGoProvider
CodexProvider
```

### Networking

Use `URLSession` with a 10-second timeout.

Conceptual request:

```swift
var request = URLRequest(url: url)
request.httpMethod = "GET"
request.timeoutInterval = 10
request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
```

Never log request headers containing credentials.

### Concurrent refresh

Fetch providers concurrently with Swift concurrency:

```swift
async let commandCode = commandCodeProvider.fetch()
async let openCode = openCodeProvider.fetch()
```

Isolate provider failures so one failed request never hides or blocks the other provider.

### Refresh cadence

Use the same default as Windows:

```text
5 minutes / 300 seconds
```

Also refresh:

```text
at startup
on manual Refresh Now
on wake from sleep
after network recovery when practical
```

### Sleep/wake handling

Listen for:

```text
NSWorkspace.didWakeNotification
```

Trigger an immediate background refresh after wake so stale values are not shown for hours.

### Cache

Use:

```text
~/Library/Caches/AIUsageMonitor/cache.json
```

Cache only normalized usage data and timestamps. Never cache credentials.

On fetch failure:

```text
show last successful values
mark provider stale
show last successful update time
```

### Preferences

Use `UserDefaults` for non-secret settings:

```text
refresh interval
warning threshold
critical threshold
launch at login
notifications enabled
```

Never store API keys in `UserDefaults`.

### Launch at login

Use modern macOS `SMAppService`.

Conceptually:

```swift
SMAppService.mainApp.register()
SMAppService.mainApp.unregister()
```

Expose this as a menu toggle:

```text
Launch at Login
```

### Notifications

Use `UserNotifications`.

Notify only on downward threshold transitions, for example:

```text
OpenCode Go monthly usage has 18% remaining.
CommandCode weekly usage has 14% remaining.
```

Track the previous state (`normal`, `warning`, `critical`) and do not repeat alerts on every refresh.

### Appearance

Use native semantic colors and SF Symbols so the app behaves properly in Light and Dark Mode.

Useful symbols:

```text
gauge.with.dots.needle.50percent
chart.bar
exclamationmark.triangle
arrow.clockwise
```

### Logging

Preferred options:

```text
~/Library/Logs/AIUsageMonitor/usage-monitor.log
```

or Apple unified logging with `Logger` / `os.Logger`.

Log:

```text
startup
provider refresh success/failure
HTTP status category
schema mismatch
manual refresh
launch-at-login changes
notification threshold transitions
```

Never log credentials or Authorization headers.

### Provider health model

Use the same cross-platform statuses:

```text
OK
STALE
AUTH_ERROR
NETWORK_ERROR
SCHEMA_ERROR
API_ERROR
```

### Graceful degradation

If only one provider fails, keep the other visible.

Example:

```text
CommandCode
97 / 99 / 87

OpenCode Go
Authentication required
```

or:

```text
CommandCode
Unavailable

OpenCode Go
100 / 99 / 86
```

The app should not quit because an API request fails.

### macOS project structure

Recommended native structure:

```text
AIUsageMonitor/
│
├── AIUsageMonitorApp.swift
├── Models/
│   ├── UsageWindow.swift
│   └── ProviderUsage.swift
│
├── Providers/
│   ├── UsageProvider.swift
│   ├── CommandCodeProvider.swift
│   └── OpenCodeGoProvider.swift
│
├── Services/
│   ├── UsageRefreshService.swift
│   ├── CacheService.swift
│   ├── CredentialService.swift
│   └── NotificationService.swift
│
├── Views/
│   ├── MenuBarView.swift
│   ├── DetailView.swift
│   ├── ProviderView.swift
│   └── UsageWindowView.swift
│
└── Utilities/
    ├── DateFormatting.swift
    └── Logging.swift
```

### Distribution

For development, run from Xcode.

For distribution:

```text
Archive in Xcode
sign with Developer ID
use Hardened Runtime
notarize with Apple
staple notarization ticket
```

Signing/notarization can be deferred for personal-development builds.

### Cross-platform parity

```text
Feature                    Windows tray      macOS menu bar
------------------------------------------------------------
5-minute refresh            Yes               Yes
Manual refresh              Yes               Yes
Detailed view               Yes               Yes
Start/launch at login       Yes               Yes
Threshold notifications     Yes               Yes
Stale-data cache            Yes               Yes
CommandCode support         Yes               Yes
OpenCode Go support         Yes               Yes
Local-time reset display    Yes               Yes
Secret-free logs            Yes               Yes
Independent provider errors Yes               Yes
```

### Recommended build sequence

```text
Phase 1   shared/provider data layer + CLI validation
Phase 2   Windows tray app
Phase 3   macOS SwiftUI MenuBarExtra app
Phase 4   notifications, launch-at-login, cache, packaging polish
```

If a faster macOS prototype is desired before SwiftUI, add:

```text
Phase 2.5   Python + rumps menu-bar prototype
```

### macOS success criteria

The macOS version is complete when:

```text
it runs as a menu bar app without a terminal window
it shows all six usage windows
it refreshes every 5 minutes
manual refresh works
reset/renewal times display in local time
sleep/wake refresh works
Launch at Login works
threshold notifications work
credentials are never duplicated into app config
secrets are never logged
one provider can fail without hiding the other
```
