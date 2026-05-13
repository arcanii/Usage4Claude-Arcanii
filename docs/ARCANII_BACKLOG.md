# Arcanii Mod — Improvement Backlog

Companion to [ARCANII_DESIGN.md](ARCANII_DESIGN.md). Items grouped by effort. None are scheduled — pick one when there's time.

## Status as of v1.6.3

✅ All P0 (3 items) and P1 (5 items) — shipped in v1.2.0.
✅ All P2 (5 items) — shipped in v1.2.0.
✅ All P3 (4 items) — shipped: account-switching shortcut + CSV export in v1.2.0; **Sparkle in-app updates** in v1.3.0/v1.3.2; **desktop widget** in v1.4.0.

## Open follow-ups

- [ ] **Localize the Extra Usage currency symbol.** Display strings still hardcode `$` regardless of the user's billing currency. Upstream fixed this in v2.6.1 (commit `4dc411b`) by mapping `ExtraUsageData.currency` (USD/EUR/JPY/KRW/GBP/etc.) to the right symbol. Skipped during the v1.5.1 v2.6.1 backport because Bryan is billed in USD — flag for non-USD users if the fork ever picks them up. Touches `extra_usage.usage_amount` / `extra_usage.remaining_amount` in all 5 locales plus `formattedCompactAmount`. **(S)**

- [ ] **Bump Chrome user-agent recurringly.** v1.4.1 sets it to Chrome 148; real Chrome keeps marching on. Either add a build step that fetches the current major from a known config endpoint, or set a calendar reminder to bump quarterly. **(S — recurring)**

- [ ] **Bundle ID cleanup for the widget.** Xcode auto-named the widget bundle `com.arcanii.Usage4Claude.Usage4ClaudeWidget` (awkward double "Widget"). Renaming to `com.arcanii.Usage4Claude.Widget` would invalidate the App Group profile that's already provisioned for the current id, so it's not free — but cleaner long-term. **(S)**

- [ ] **iOS continuity for Control Center accessory widgets.** Planned for v1.6.0 but dropped — `.accessoryCircular` / `.accessoryRectangular` / `.accessoryInline` widget families are iOS/watchOS only on macOS Widget extensions. Bringing them in via iOS continuity (a separate target with iOS deployment) would unlock pin-to-Control-Center variants on macOS Sonoma+. Not free — adds App Store / TestFlight / signing complexity. **(M, optional)**

## Closed in v1.6.3

- ✅ **Japanese kanji `時` (U+6642)** for the 24h-format hour suffix in `TimeFormatHelper.formatDateHour`. Previously rendered as the Simplified Chinese `时` (U+65F6) for Japanese users. Backport of upstream `753b6bc`.
- ✅ **Session Key hint wording generalized** — removed the obsolete `sk-ant-sid01-` reference from the auth-settings and welcome hints in all 5 locales, plus the doc-comment example in `SensitiveDataRedactor`. Backport of upstream `48bccc9`.

## Closed in v1.6.2

- ✅ **In-app "Reset Widgets" recovery** — popover `…` menu now has a Reset Widgets action: default click does a medium reset (snapshot rewrite + timeline reload + config cache invalidation), ⌥-click escalates to a hard reset (`killall chronod`). Backed by new `WidgetReloader` helper. Removes the need to drop to Terminal when chronod state wedges.

## Closed in v1.6.1

- ✅ **Refresh on system wake** — `DataRefreshManager` subscribes to `NSWorkspace.didWakeNotification` and fetches ~3s post-wake. Backport of upstream `de671c6`.
- ✅ **Smart-mode idle→active timer restart** — popover-open and manual refresh now restart the timer when transitioning out of an idle tier. Same upstream commit.
- ✅ **Always show 5h + 7d in smart mode** — `getActiveDisplayTypes` no longer hides them when data is missing. Backport of upstream `fffff55`.
- ✅ **7-day placeholder for new accounts** — `toUsageData()` emits a 0% placeholder when 7-day data is absent. `addAccount` posts `.accountChanged` after the first add. Backport of upstream `1192f35`.

## Closed in v1.6.0

- ✅ **NDJSON history store** — replaced the per-fetch full-file JSON rewrite with an O(1) append into `~/Library/Group Containers/.../usage-history.ndjson`. Migration on first launch drains the legacy file. Capped at 10k samples; compaction on launch.
- ✅ **History surfaced in the popover** — every limit row now shows a 24h sparkline strip (color-matched to the row, live-updating via `@ObservedObject UsageHistoryStore.shared`).
- ✅ **Four new widget kinds** — Large Dashboard (all 5 limits), Sparkline (small + medium, ring + 24h trend), Dual Sparkline (medium, 5h + 7d side-by-side), ExtraLarge (full dashboard + combined sparkline strip).
- ✅ **Reusable `SparklineView`** — pure SwiftUI Path-based component shared between popover and widget extension (zero AppKit / `L.*` / `UserSettings` dependencies).

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
