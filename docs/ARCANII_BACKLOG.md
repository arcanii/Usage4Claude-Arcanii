# Arcanii Mod — Improvement Backlog

Companion to [ARCANII_DESIGN.md](ARCANII_DESIGN.md). Items grouped by effort. None are scheduled — pick one when there's time.

## Status as of v1.4.1

✅ All P0 (3 items) and P1 (5 items) — shipped in v1.2.0.
✅ All P2 (5 items) — shipped in v1.2.0.
✅ All P3 (4 items) — shipped: account-switching shortcut + CSV export in v1.2.0; **Sparkle in-app updates** in v1.3.0/v1.3.2; **desktop widget** in v1.4.0.

## Open follow-ups

- [ ] **Add tests for `UsageResponse.toUsageData()` and `ExtraUsageResponse.toExtraUsageData()`.** Both are pure JSON → struct transformations with non-trivial fallback logic for legacy fields. Currently live inside `ClaudeAPIService.swift`; extracting just the response models into their own file would unlock testing them in the existing SwiftPM suite. **(S)**

- [ ] **Migrate `fetchOrganizations` to async/await internally.** Three callsites (`AuthSettingsView`, `WelcomeView`, `WebLoginCoordinator`) still use the completion-handler form; converting them at the same time gives the public API a clean `async throws -> [Organization]` shape. **(S)**

- [ ] **Persist usage history more efficiently.** v1.2.0 writes the full JSON file on every fetch tick. For very long-running installs that adds up. Move to NDJSON (append-only) with periodic compaction, or use a tiny SQLite. **(M)**

- [ ] **Surface usage history in the popover.** v1.2.0 captures the data and exports CSV, but the popover still only shows the latest snapshot. A small sparkline of the last N hours (or a separate "History" tab in the detail view) would make the data visible without exporting. **(M)**

- [ ] **Bump Chrome user-agent recurringly.** v1.4.1 sets it to Chrome 148; real Chrome keeps marching on. Either add a build step that fetches the current major from a known config endpoint, or set a calendar reminder to bump quarterly. **(S — recurring)**

- [ ] **Bundle ID cleanup for the widget.** Xcode auto-named the widget bundle `com.arcanii.Usage4Claude.Usage4ClaudeWidget` (awkward double "Widget"). Renaming to `com.arcanii.Usage4Claude.Widget` would invalidate the App Group profile that's already provisioned for the current id, so it's not free — but cleaner long-term. **(S)**

## Closed in v1.4.1

- ✅ **Ring illumination slider** — exposed in General Settings ("Popover Appearance" card). Scales shadow opacity/radius linearly; gates `.glassEffect(in:)` at a 0.5 threshold.
- ✅ **Auto-relogin throttle validated and fixed** — the `sessionExpiredPrompted` flag now clears on explicit user retry (manual refresh, popover-open fetch), so dismissing WebLogin no longer leaves the user stuck waiting for an impossible successful fetch to unstick the prompt.
- ✅ **Chrome user-agent bumped** — 140 → 148 (current macOS Chrome stable as of 2026-05).

## Effort key

- **XS** — under an hour
- **S** — half day
- **M** — 1–2 days
- **L** — 3+ days
