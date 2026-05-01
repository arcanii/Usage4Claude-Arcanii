# Arcanii Mod — Improvement Backlog

Companion to [ARCANII_DESIGN.md](ARCANII_DESIGN.md). Items grouped by effort. None are scheduled — pick one when there's time.

## Status as of v1.4.0

✅ All P0 (3 items) and P1 (5 items) — shipped in v1.2.0.
✅ All P2 (5 items) — shipped in v1.2.0.
✅ All P3 (4 items) — shipped: account-switching shortcut + CSV export in v1.2.0; **Sparkle in-app updates** in v1.3.0/v1.3.2; **desktop widget** in v1.4.0.

## Open follow-ups

- [ ] **Add tests for `UsageResponse.toUsageData()` and `ExtraUsageResponse.toExtraUsageData()`.** Both are pure JSON → struct transformations with non-trivial fallback logic for legacy fields. Currently live inside `ClaudeAPIService.swift`; extracting just the response models into their own file would unlock testing them in the existing SwiftPM suite. **(S)**

- [ ] **Migrate `fetchOrganizations` to async/await internally.** Three callsites (`AuthSettingsView`, `WelcomeView`, `WebLoginCoordinator`) still use the completion-handler form; converting them at the same time gives the public API a clean `async throws -> [Organization]` shape. **(S)**

- [ ] **Persist usage history more efficiently.** v1.2.0 writes the full JSON file on every fetch tick. For very long-running installs that adds up. Move to NDJSON (append-only) with periodic compaction, or use a tiny SQLite. **(M)**

- [ ] **Surface usage history in the popover.** v1.2.0 captures the data and exports CSV, but the popover still only shows the latest snapshot. A small sparkline of the last N hours (or a separate "History" tab in the detail view) would make the data visible without exporting. **(M)**

- [ ] **Ring illumination slider.** v1.3.1 added a glass-tube glow on the popover rings (stacked-shadow + `.glassEffect(in:)`). The intensity is hard-coded. Expose a slider in General Settings ("Ring illumination" 0–100%) that scales the shadow opacities and radii so users can dial it from "off" through "subtle" to "vivid". State lives on `UserSettings`; rings read it in their `.shadow` modifiers. The macOS-26 `.glassEffect(in:)` itself isn't easily continuous so it could just toggle on/off at a threshold (e.g. only apply above 50%). **(S)**

- [ ] **Validate the auto-relogin throttle in practice.** v1.2.0 prompts re-login on the first `.sessionExpired` after a previously valid session, then blocks until the next successful fetch resets the flag. If a user dismisses the WebLogin window without logging in, the next refresh tick won't re-prompt — they'd have to manually trigger a refresh. Probably fine, but worth a real-world check. **(XS — verification only)**

- [ ] **Bump Chrome user-agent recurringly.** v1.4.0 still sets it to Chrome 140; real Chrome marches on. Either add a build step that fetches the current major from a known config endpoint, or set a calendar reminder to bump quarterly. **(S — recurring)**

- [ ] **Bundle ID cleanup for the widget.** Xcode auto-named the widget bundle `com.arcanii.Usage4Claude.Usage4ClaudeWidget` (awkward double "Widget"). Renaming to `com.arcanii.Usage4Claude.Widget` would invalidate the App Group profile that's already provisioned for the current id, so it's not free — but cleaner long-term. **(S)**

## Effort key

- **XS** — under an hour
- **S** — half day
- **M** — 1–2 days
- **L** — 3+ days
