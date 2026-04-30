# Arcanii Mod — Improvement Backlog

Companion to [ARCANII_DESIGN.md](ARCANII_DESIGN.md). Items grouped by priority and tagged with rough effort. None are scheduled — pick one when there's time.

## Status as of v1.2.0

✅ All P0 (3 items) and P1 (5 items) — landed in the v1.2.0 commits.
✅ All P2 (5 items) — landed in v1.2.0.
✅ P3-1 account-switching shortcut, P3-3 CSV export — landed in v1.2.0.
🟡 P3-2 (Sparkle) and P3-4 (Widget) — deferred to their own sessions, see below.

## Deferred — own session each

- [ ] **Sparkle (or equivalent) for in-app updates.** `UpdateChecker` only opens the DMG download URL — the user has to drag the new app into Applications themselves. Sparkle would make this a one-click update with a signature-verified delta. Requires hosting an appcast feed (GitHub Pages works), generating an EdDSA signing key, and replacing the `NSAlert` flow with Sparkle's. **(L)**

- [ ] **Widget / Live Activity.** macOS 14+ allows widgets in Notification Center. Could mirror the menu bar rings in a larger format and show the Extra Usage spend trend. Requires a new widget extension target. **(M)**

## Cross-cutting follow-ups (new since v1.2.0)

- [ ] **Add tests for `UsageResponse.toUsageData()` and `ExtraUsageResponse.toExtraUsageData()`.** Both are pure JSON → struct transformations with non-trivial fallback logic for legacy fields. Currently live inside `ClaudeAPIService.swift`; extracting just the response models into their own file would unlock testing them in the existing SwiftPM suite. **(S)**

- [ ] **Migrate `fetchOrganizations` to async/await internally.** Three callsites (`AuthSettingsView`, `WelcomeView`, `WebLoginCoordinator`) still use the completion-handler form; converting them at the same time gives the public API a clean `async throws -> [Organization]` shape. **(S)**

- [ ] **Persist usage history more efficiently.** v1.2.0 writes the full JSON file on every fetch tick. For very long-running installs that adds up. Move to NDJSON (append-only) with periodic compaction, or use a tiny SQLite. **(M)**

- [ ] **Surface usage history in the popover.** v1.2.0 captures the data and exports CSV, but the popover still only shows the latest snapshot. A small sparkline of the last N hours (or a separate "History" tab in the detail view) would make the data visible without exporting. **(M)**

- [ ] **Validate the auto-relogin throttle in practice.** v1.2.0 prompts re-login on the first `.sessionExpired` after a previously valid session, then blocks until the next successful fetch resets the flag. If a user dismisses the WebLogin window without logging in, the next refresh tick won't re-prompt — they'd have to manually trigger a refresh. Probably fine, but worth a real-world check. **(XS — verification only)**

- [ ] **Bump Chrome user-agent recurringly.** v1.2.0 set it to Chrome 140; real Chrome will be ahead of that within months. Either add a build step that fetches the current major from a known config endpoint, or set a calendar reminder to bump quarterly. **(S — recurring)**

## Effort key

- **XS** — under an hour
- **S** — half day
- **M** — 1–2 days
- **L** — 3+ days
