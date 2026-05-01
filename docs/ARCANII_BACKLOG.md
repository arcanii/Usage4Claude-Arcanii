# Arcanii Mod — Improvement Backlog

Companion to [ARCANII_DESIGN.md](ARCANII_DESIGN.md). Items grouped by effort. None are scheduled — pick one when there's time.

## Status as of v1.5.1

✅ All P0 (3 items) and P1 (5 items) — shipped in v1.2.0.
✅ All P2 (5 items) — shipped in v1.2.0.
✅ All P3 (4 items) — shipped: account-switching shortcut + CSV export in v1.2.0; **Sparkle in-app updates** in v1.3.0/v1.3.2; **desktop widget** in v1.4.0.

## Open follow-ups

- [ ] **Localize the Extra Usage currency symbol.** Display strings still hardcode `$` regardless of the user's billing currency. Upstream fixed this in v2.6.1 (commit `4dc411b`) by mapping `ExtraUsageData.currency` (USD/EUR/JPY/KRW/GBP/etc.) to the right symbol. Skipped during the v1.5.1 v2.6.1 backport because Bryan is billed in USD — flag for non-USD users if the fork ever picks them up. Touches `extra_usage.usage_amount` / `extra_usage.remaining_amount` in all 5 locales plus `formattedCompactAmount`. **(S)**

- [ ] **Persist usage history more efficiently.** v1.2.0 writes the full JSON file on every fetch tick. For very long-running installs that adds up. Move to NDJSON (append-only) with periodic compaction, or use a tiny SQLite. **(M)**

- [ ] **Surface usage history in the popover.** v1.2.0 captures the data and exports CSV, but the popover still only shows the latest snapshot. A small sparkline of the last N hours (or a separate "History" tab in the detail view) would make the data visible without exporting. **(M)**

- [ ] **Bump Chrome user-agent recurringly.** v1.4.1 sets it to Chrome 148; real Chrome keeps marching on. Either add a build step that fetches the current major from a known config endpoint, or set a calendar reminder to bump quarterly. **(S — recurring)**

- [ ] **Bundle ID cleanup for the widget.** Xcode auto-named the widget bundle `com.arcanii.Usage4Claude.Usage4ClaudeWidget` (awkward double "Widget"). Renaming to `com.arcanii.Usage4Claude.Widget` would invalidate the App Group profile that's already provisioned for the current id, so it's not free — but cleaner long-term. **(S)**

## Closed in v1.5.1

- ✅ **HTTP/3 disabled on Claude API requests** — `request.assumesHTTP3Capable = false` on all three endpoints. Backported from upstream v2.6.1 (`9feb1fc`). Prevents UDP from sneaking around TCP-only system proxies.
- ✅ **Extra Usage cents precision** — `usage_amount` and `remaining_amount` now use `%.2f` for the *used* portion (limit stays `%.0f`). Backported from upstream v2.6.1 (`42c7f56`). 5 locales updated.

## Closed in v1.5.0

- ✅ **Response-model tests** — `UsageResponse.toUsageData()` and `ExtraUsageResponse.toExtraUsageData()` covered by 24 new tests in `Tests/Usage4ClaudeCoreTests/`. Models extracted into [ClaudeAPIResponseModels.swift](../Usage4Claude/Helpers/ClaudeAPIResponseModels.swift) so the SwiftPM target can compile them without dragging in `L.*` / `UserSettings`. Test count 11 → 35.
- ✅ **`fetchOrganizations` migrated to async/await** — public API is now `async throws -> [Organization]`. All three callsites converted in lockstep.

## Closed in v1.4.1

- ✅ **Ring illumination slider** — exposed in General Settings ("Popover Appearance" card). Scales shadow opacity/radius linearly; gates `.glassEffect(in:)` at a 0.5 threshold.
- ✅ **Auto-relogin throttle validated and fixed** — the `sessionExpiredPrompted` flag now clears on explicit user retry (manual refresh, popover-open fetch), so dismissing WebLogin no longer leaves the user stuck waiting for an impossible successful fetch to unstick the prompt.
- ✅ **Chrome user-agent bumped** — 140 → 148 (current macOS Chrome stable as of 2026-05).

## Effort key

- **XS** — under an hour
- **S** — half day
- **M** — 1–2 days
- **L** — 3+ days
