# U4Claude (Arcanii Mod) — Design

A snapshot of how the app is wired today (v1.1.0). Companion to [ARCANII_BACKLOG.md](ARCANII_BACKLOG.md), which captures the gaps and improvement ideas.

For broader context inherited from upstream, see [PROJECT_SUMMARY.md](PROJECT_SUMMARY.md) and [usage4claude-v2-spec.md](usage4claude-v2-spec.md).

## What it is

A macOS menu bar app that polls the private `claude.ai/api/organizations/<id>/usage` endpoint and renders the user's 5-hour, 7-day, Opus, Sonnet, and Extra Usage limits as compact rings/numbers in the menu bar. Authentication is by session cookie scraped from a logged-in WebView.

- Bundle id: `com.arcanii.Usage4Claude`
- Product name: `U4Claude.app` (renamed from upstream's `Usage4Claude.app` so both can coexist)
- macOS deployment target: 13.0
- Universal binary (x86_64 + arm64)

## Module map

```
Usage4Claude/
├── App/
│   ├── ClaudeUsageMonitorApp.swift     entry point + AppDelegate
│   ├── MenuBarManager.swift            owns the status item, popover, settings window
│   ├── MenuBarUI.swift                 NSStatusItem + NSPopover plumbing
│   └── MenuBarIconRenderer.swift       draws the menu bar icon (4 display modes)
├── Helpers/
│   ├── DataRefreshManager.swift        timer-driven fetch loop, smart-mode logic
│   ├── TimerManager.swift              keyed timer registry
│   ├── ColorScheme.swift               percentage → color
│   ├── ShapeIconRenderer.swift         per-limit shape icons (rect/hex)
│   ├── IconShapePaths.swift            bezier shapes
│   ├── DiagnosticManager.swift         captures redacted reports for support
│   ├── SensitiveDataRedactor.swift     redacts session keys/IDs from diagnostics
│   ├── LocalizationManager.swift       runtime language switching
│   └── …
├── Models/
│   ├── UserSettings.swift              singleton UserDefaults-backed prefs (1290 lines)
│   ├── Account.swift                   multi-account model
│   └── DiagnosticReport.swift
├── Services/
│   ├── ClaudeAPIService.swift          HTTP to claude.ai (1028 lines)
│   ├── ClaudeAPIHeaderBuilder.swift    spoofed Chrome headers (Cloudflare bypass)
│   ├── KeychainManager.swift           credential storage (Keychain in Release; UserDefaults in Debug)
│   ├── NotificationManager.swift       UserNotifications wrapper
│   └── UpdateChecker.swift             GitHub Releases poll
└── Views/
    ├── SettingsView.swift              3-tab settings shell
    ├── Settings/Tabs/
    │   ├── GeneralSettingsView.swift   display mode, refresh, debug card (#if DEBUG)
    │   ├── AuthSettingsView.swift      session/org config, multi-account list
    │   └── AboutView.swift             version + build + copyright + GitHub link
    ├── Settings/Welcome/WelcomeView.swift
    ├── UsageDetail/                    popover view with per-limit rows
    ├── WebLogin/                       WKWebView that scrapes the session cookie
    └── DiagnosticsView.swift           support report exporter
```

## Data flow

### Launch

1. `ClaudeUsageMonitorApp` creates `AppDelegate`.
2. `AppDelegate.applicationDidFinishLaunching` sets the activation policy to `.accessory` (no Dock icon) and instantiates `MenuBarManager`.
3. If `UserSettings.isFirstLaunch || !hasValidCredentials`, the welcome window opens. Otherwise `MenuBarManager.startRefreshing()` kicks off the data loop.
4. `MenuBarManager` constructs `MenuBarUI` (status item + popover) and `DataRefreshManager`. Combine bindings sync `usageData`, `isLoading`, `errorMessage`, and `hasAvailableUpdate` from the data manager into the menu bar manager so view updates flow through SwiftUI.

### Authentication

1. User clicks "log in" in the welcome or auth settings view.
2. `WebLoginCoordinator` opens `claude.ai` in a `WKWebView`.
3. After the user signs in, the coordinator reads the `sessionKey` cookie from the shared cookie storage and lists organizations via `ClaudeAPIService.fetchOrganizations`.
4. The chosen org's UUID + the session key are persisted via `KeychainManager` (Keychain in Release, UserDefaults in Debug for dev convenience).

### Periodic refresh

```
DataRefreshManager
    └── TimerManager schedules "mainRefresh" with settings.effectiveRefreshInterval
        └── on tick: fetchUsage()
            ├── ClaudeAPIService.fetchMainUsage   (claude.ai/api/organizations/<id>/usage)
            └── ClaudeAPIService.fetchExtraUsage  (…/overage_spend_limit)
                  (parallel via DispatchGroup; Extra Usage failure is silently swallowed)

On success → publish UsageData; smart mode adjusts the next interval; if the
reset time changed, reset-verification timers are scheduled at +1s/+10s/+30s.

On failure → publish errorMessage; the menu bar icon shows the placeholder
ring.
```

Smart mode (`UserSettings.refreshMode == .smart`) shortens the interval when usage is changing and lengthens it when idle. Manual refresh and opening the popover both force a switch back to the active interval.

### App Nap

`DataRefreshManager.beginRefreshActivity` holds a `ProcessInfo.beginActivity` token (`userInitiatedAllowingIdleSystemSleep`) while refreshing is active. Without this, macOS App Nap freezes the timers when the app has been backgrounded.

### Cloudflare bypass

`ClaudeAPIHeaderBuilder` injects a static set of Chrome-like headers (user-agent, sec-fetch-*, origin, referer) plus the session cookie. Anthropic's edge sometimes returns a Cloudflare HTML challenge in place of JSON; `fetchMainUsage` checks the body for `<!DOCTYPE html>` / `<html` and surfaces `.cloudflareBlocked` in that case.

### Error surface

`UsageError` cases: `invalidURL`, `noData`, `sessionExpired`, `cloudflareBlocked`, `noCredentials`, `networkError`, `decodingError`, `unauthorized`, `rateLimited`, `httpError(statusCode:)`. The mapping from HTTP status code happens in `fetchMainUsage`:

| HTTP | Mapped to                                                      |
|------|---------------------------------------------------------------- |
| 200  | parsed `UsageResponse`                                         |
| 401  | `.unauthorized`                                                |
| 403  | `.sessionExpired` if body is `permission_error`, else `.cloudflareBlocked` (fixed in v1.1.0; previously always `.cloudflareBlocked`) |
| 429  | `.rateLimited`                                                 |
| HTML body at any 2xx | `.cloudflareBlocked`                                  |

### Update checking

`UpdateChecker` polls `https://api.github.com/repos/arcanii/Usage4Claude-Arcanii/releases/latest` once at launch and then every 24 hours. It compares semantic versions and either silently sets `hasAvailableUpdate` (background) or shows an `NSAlert` with download/remind/details buttons (manual). Manual checks pop a dialog even when no update is available.

## Settings & state

`UserSettings.shared` is a singleton ObservableObject backed by `UserDefaults`. ~1290 lines covering:

- Display mode (`percentageOnly`, `iconOnly`, `both`, `unified`) and style (`colorTranslucent`, `colorWithBackground`, `monochrome`).
- Refresh mode (`smart` / `fixed`) and interval; smart-mode counters.
- Per-limit visibility flags (5-hour, 7-day, Opus, Sonnet, Extra Usage).
- Notification preferences and thresholds.
- Multi-account list (UUID + session key per org); current account.
- Launch-at-login state via `SMAppService`.
- Debug-only: simulate-update flag, mock percentage sliders, "keep detail window open" flag — all `#if DEBUG`-gated and embedded in the General tab.

## Build & distribution

`scripts/build.sh` is the single distribution entry point. Default invocation:

```
./scripts/build.sh
```

Steps (Release config):

1. `xcodebuild clean`
2. `xcodebuild archive` with manual signing override → `Developer ID Application: Matthew Mark (386M76FV3K)`
3. `xcodebuild -exportArchive` with `method = developer-id`
4. `create-dmg` produces `U4Claude-v<version>.dmg` with the app shortcut layout
5. `xcrun notarytool submit --wait` against the `Usage4Claude-Arcanii-notarize` keychain profile (skipped with a warning if profile missing; configurable via `NOTARY_PROFILE` env var)
6. `xcrun stapler staple` if notarization succeeded

Output lands in `build/Usage4Claude-Release-<version>/`. The previously shipped DMG can also be found at `build/release/U4Claude-v1.0.0.dmg`.

`DEVELOPER_DIR` is set to `/Applications/Xcode.app/Contents/Developer` at the top of the script because `xcode-select` on this machine points at CommandLineTools.

## Logging

`LoggerExtension` defines per-category `Logger` instances (`menuBar`, `settings`, `keychain`, `api`, `localization`) under the bundle identifier subsystem. View at runtime with:

```
log show --predicate 'subsystem == "com.arcanii.Usage4Claude"' --info --debug --last 30m
```

Log messages are a mix of Chinese (legacy from upstream) and English — see the backlog.
