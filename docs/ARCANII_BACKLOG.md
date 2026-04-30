# Arcanii Mod — Improvement Backlog

Companion to [ARCANII_DESIGN.md](ARCANII_DESIGN.md). Items grouped by priority and tagged with rough effort. None are scheduled — pick one when there's time.

## P0 — User-visible bugs / friction

- [ ] **Auto-prompt re-login on session expiry.** When `UsageError.sessionExpired` fires, the menu bar shows the placeholder icon and the popover surfaces an error message — but the user has to manually navigate to Auth Settings and re-run the WebLogin flow. Should detect `.sessionExpired`, post a notification, and open the WebLoginCoordinator directly. **(M)**

- [ ] **Extra Usage 403 swallows session-invalid errors silently.** `fetchExtraUsage` returns `.success(nil)` for any 403, treating it as "feature not enabled". When the session is actually expired, the main API surfaces it but the Extra Usage code path masks it. Apply the same `permission_error` body inspection as `fetchMainUsage`, then defer to the main API's error. **(S)**

- [ ] **Cloudflare HTML detection is a substring search.** `fetchMainUsage` checks for `<!DOCTYPE html>` or `<html` in the response body to identify a Cloudflare challenge. This will misfire on any future API error that happens to embed HTML. Switch to inspecting `Content-Type: text/html` on the response. **(XS)**

## P1 — Reliability & DX

- [ ] **`DataRefreshManager.init` schedules a daily update check before credentials exist.** First launch fires a GitHub Releases request that's wasted if the user is still on the welcome screen. Move `scheduleDailyUpdateCheck` into `startRefreshing` or guard on `hasValidCredentials`. **(XS)**

- [ ] **No tests.** No XCTest target. The error-mapping logic in `ClaudeAPIService.fetchMainUsage`, the smart-mode interval calculation in `UserSettings`, and the version comparison in `UpdateChecker.isNewerVersion` are pure functions begging for unit tests. **(M)**

- [ ] **Adopt async/await in `ClaudeAPIService`.** `fetchUsage` uses `DispatchGroup` + completion handlers, which obscures the parallel-fetch + merge logic and makes cancellation awkward. A `Task.withTaskGroup` rewrite would be ~half the lines. **(M)**

- [ ] **`UserSettings.swift` is 1290 lines.** Mixes display config, refresh logic, smart-mode counters, account list, debug flags, notification thresholds, and launch-at-login. Splitting into `UserSettings`, `DisplayPreferences`, `RefreshPreferences`, `AccountStore`, and `LaunchAtLogin` would make each piece testable in isolation. **(L)**

- [ ] **Notarization profile name is hard-coded in the build script.** `Usage4Claude-Arcanii-notarize` is the default; can be overridden via `NOTARY_PROFILE` env var. Move into a gitignored `scripts/build.config` (or `.env`) so other contributors can ship their own builds without editing the script. **(S)**

## P2 — Polish

- [ ] **Mixed-language log messages.** `Logger.menuBar.error("API 请求失败: ...")` etc. — half English, half Chinese (inherited from upstream). Pick one (English, since this is the Arcanii fork). **(S)**

- [ ] **`art/` is untracked.** The icon source PNG (`Usage4Claude-Arcanii.png`) lives outside the repo. Either commit it to `docs/images/` or delete it. Pick one. **(XS)**

- [ ] **`build/release/U4Claude-v1.0.0.dmg` is checked into the working tree (but ignored by `.gitignore`).** Remove from disk; the canonical release artifact is now built fresh by the script into `build/Usage4Claude-Release-<version>/`. **(XS)**

- [ ] **About tab shows "Usage4Claude" + "(Arcanii Mod)" stacked.** Could just say "U4Claude" since that's the actual product/binary name. Cosmetic. **(XS)**

- [ ] **Spoofed Chrome 131 user-agent.** Real Chrome marches on; eventually Cloudflare's heuristics may flag a stale UA. Either bump periodically or fetch the current major from a config. **(S — but recurring)**

## P3 — New features

- [ ] **Sparkle (or equivalent) for in-app updates.** `UpdateChecker` only opens the DMG download URL — the user has to drag the new app into Applications themselves. Sparkle would make this a one-click update with a signature-verified delta. Requires hosting an appcast feed. **(L)**

- [ ] **Account-switching keyboard shortcut.** Multi-account is supported but switching requires right-click → menu. A global hotkey (or `⌘1/⌘2/...` while popover is open) would help heavy users. **(S)**

- [ ] **CSV / JSON export of usage history.** App currently shows only the latest snapshot. Persisting a rolling window (e.g. last 30 days, sampled at refresh intervals) and exposing an export button in DiagnosticsView would help users track spend trends. **(M)**

- [ ] **Widget / Live Activity.** macOS 14+ allows widgets in Notification Center. Could mirror the menu bar rings in a larger format. **(M)**

## Effort key

- **XS** — under an hour
- **S** — half day
- **M** — 1–2 days
- **L** — 3+ days
