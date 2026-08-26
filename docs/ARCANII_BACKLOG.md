# Arcanii Mod — Improvement Backlog

Companion to [ARCANII_DESIGN.md](ARCANII_DESIGN.md). Items grouped by effort. None are scheduled — pick one when there's time.

## Status as of v1.8.0

✅ **v1.8.0** — system-browser OAuth (PKCE) sign-in (upstream #49), custom-display "menu bar only" toggle, Extra Usage fractional-credits decode fix, 403 error-classification fix, and localization fixes (HTTP-error text + auth-error "Go to Settings" button). OAuth callback listener hardened to loopback-only. Ports 1–5 from [UPSTREAM_PORT_AUDIT.md](UPSTREAM_PORT_AUDIT.md); verified on a real Sparkle upgrade.
✅ All P0 (3 items) and P1 (5 items) — shipped in v1.2.0.
✅ All P2 (5 items) — shipped in v1.2.0.
✅ All P3 (4 items) — shipped: account-switching shortcut + CSV export in v1.2.0; **Sparkle in-app updates** in v1.3.0/v1.3.2; **desktop widget** in v1.4.0.
✅ **App Sandbox** flipped on in v1.7.0 — main app + widget both sandboxed. Cost: Reset Widgets retirement, one-click re-login on update.

## Open follow-ups

- [x] **Localize the Extra Usage currency symbol** — *implemented 2026-06-02, pending release.* New `ExtraUsageData.currencySymbol` maps ISO 4217 codes → glyphs (USD/EUR/GBP/JPY/KRW/CAD/AUD/BRL/INR; raw-code fallback), threaded through `usageAmount` / `remainingAmount` / `formattedCompactAmount`; all 5 locales switched from hardcoded `$` to a `%@` placeholder. Backport of upstream `4dc411b` (v2.6.1) + KRW (₩) for the Korean locale. +3 `ExtraUsageResponseTests` cases. **(S)**

- [ ] **Bump Chrome user-agent recurringly.** Currently Chrome 149 (`ClaudeAPIHeaderBuilder.swift`, last bumped v1.7.1); real Chrome keeps marching on. Either add a build step that fetches the current major from a known config endpoint, or set a calendar reminder to bump quarterly. **(S — recurring)** — *Lower priority since v1.8.0:* only **legacy session-key accounts** send the spoofed UA now; OAuth accounts use a Bearer token with no UA spoofing, so this decays in importance as users migrate to OAuth sign-in.

- [ ] **Bundle ID cleanup for the widget.** Xcode auto-named the widget bundle `com.arcanii.Usage4Claude.Usage4ClaudeWidget` (awkward double "Widget"). Renaming to `com.arcanii.Usage4Claude.Widget` would invalidate the App Group profile that's already provisioned for the current id, so it's not free — but cleaner long-term. **(S)**

- [ ] **iOS continuity for Control Center accessory widgets.** Planned for v1.6.0 but dropped — `.accessoryCircular` / `.accessoryRectangular` / `.accessoryInline` widget families are iOS/watchOS only on macOS Widget extensions. Bringing them in via iOS continuity (a separate target with iOS deployment) would unlock pin-to-Control-Center variants on macOS Sonoma+. Not free — adds App Store / TestFlight / signing complexity. **(M, optional)**

## Considered & rejected

- **Sparkline overlay on the popover ring** — explored 2026-06-02 (DEBUG-gated prototype in `UsageDetailView`, then reverted). Idea: tuck a faint 24h trend of the primary limit into the hero ring's center well. Rejected because:
  - **Smart mode (the default) always keeps 5h + 7d active** (`getActiveDisplayTypes` in `UserSettings.swift`), so the ring center is permanently the dual stacked-% layout — no room for a centered trend without crowding the numbers.
  - It **duplicates the per-row 24h sparkline strips** — the 5-Hour row already shows the same trend directly below the ring.
  - Gating to single-ring-only (Custom display, one circular limit) made it invisible in the default config.

  The per-row strips are the right home for history; a dedicated "History" tab/view remains a possible future direction. **(prototype effort: ~half day; verified the idea, didn't ship)**

## Closed in v1.7.0

- ✅ **App Sandbox enabled** — `com.apple.security.app-sandbox = YES` for the main app with `network.client` + App Group + Sparkle XPC `mach-lookup` exceptions. `SUEnableInstallerLauncherService = YES` in `Config/Info.plist`. Widget was already sandboxed. The pattern is now ready to drop into upstream PR #56 as the answer to f-is-h's sandbox blocker.
- ✅ **Sandbox transition bootstrap** in `UserSettings.init()` — logs `[SandboxBootstrap]` on first sandboxed launch with presence checks for major settings keys. Idempotent via `sandboxBootstrapped_v1.7` UserDefaults flag. Doesn't migrate plist directly (cfprefsd handles same-bundle-ID transitions); doesn't migrate Keychain (access-group change accepted as one-click re-login cost).
- ✅ **Reset Widgets retired** — `Usage4Claude/Helpers/WidgetReloader.swift` deleted, popover `…` button removed, 10 locale strings cleaned. The hard-reset tier needed subprocess execution (`killall chronod`), blocked under App Sandbox. The medium tier alone wasn't worth the menu real estate. Normal `WidgetCenter.shared.reloadAllTimelines()` on each successful fetch covers most refresh issues.

## Closed in v1.6.4

- ✅ **Google OAuth login fix** — added `WKUIDelegate` to `WebLoginCoordinator` so Google's `window.open()`-based OAuth flow loads back into the same `WKWebView` instead of being silently dropped. Broadened `allowedDomains` to base domains plus `youtube.com` (Google bounces through `accounts.youtube.com/CheckConnection`). Added `NSWindow.willCloseNotification` observer in `WebLoginWindowManager` so the WebView reference is released when the user closes via the window's red dot. Backport of upstream `94dabbf`.
- ✅ **"View Claude Usage" menu item replaced with "Claude Status"** pointing at status.claude.com — more useful during outages than re-opening the usage page in a browser (which duplicates what U4Claude already shows). Localization key renamed from `menu.web_usage` to `menu.claude_status` with upstream's canonical translations. Backport of upstream `5d022c5`.
- ✅ **Detail rings now visually invert in remaining mode.** Previously the row-tap toggle only swapped subtitle text; now the ring's trim runs from `used` to 1.0 (filling the available slice) and the center label flips from "Used" to "Available". New pure-function helpers `UsageRingTrimRange` + `UsageRingDisplay` in `UsageRowComponents.swift`. Ring animation curve switched from `.easeInOut` to `.spring(response: 0.42, dampingFraction: 0.78)`. Mode preference eager-initialized from UserDefaults to kill the one-frame appear flash. Backport of upstream `fdeb0c1` (skipped the `DetailUsageRingSweep` cosmetic flourish — would muddle with our existing glow shadows).

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
