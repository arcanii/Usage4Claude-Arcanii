# Upstream contribution log

Tracking what we've proposed back to [f-is-h/Usage4Claude](https://github.com/f-is-h/Usage4Claude), what's queued, and what's not worth bringing over. Companion to [ARCANII_BACKLOG.md](ARCANII_BACKLOG.md) — that file is our fork's TODO; this file is upstream-facing.

Working tree for upstream work: `~/Desktop/github_repos/Usage4Claude-fork/` (origin = `arcanii/Usage4Claude-fork`, upstream = `f-is-h/Usage4Claude`).

## Divergence policy (decided 2026-05-18)

**This fork stays Claude-only.** Upstream pivoted into a dual-provider
(Claude + Codex) app starting at v3.0.0. From there on, the large
majority of upstream commits are Codex feature-work that does not apply
here.

When syncing upstream, triage like this:

1. **Is the commit Codex-shaped?** (filename contains `Codex`/`codex`,
   or it touches `DataRefreshManager` / `DiagnosticManager` /
   `GeneralSettingsView` / WebLogin *in service of* Codex, or it adds
   Codex-only formatters/strings) → **skip.** Don't re-derive this each
   time; Codex isn't coming to this fork unless that decision is
   explicitly revisited.
2. **Is it a genuine Claude-side bug fix or general improvement?**
   (e.g. the v1.6.3 kanji + session-key-hint backports) → evaluate and
   backport as usual.

Reviewed up to upstream `a3a9f58` (v3.0.1, 2026-05-18): commits
`a982843`, `d961bab`, `a83763b`, `ff93d51` all Codex-driven, none
backported. `ff93d51`'s `formatDateMinute` helper looked generic but
exists for Codex's arbitrary-minute reset window; Claude windows reset
on the hour and we deliberately show hour precision, so porting it
would be dead code or a readability regression.

Porting Codex wholesale is a multi-week project, only justified if the
maintainer actually uses OpenAI Codex CLI. Not planned.

## Active

| # | Title | Type | State | Last update |
|---|---|---|---|---|

## Merged

| # | Title | Merged | Notes |
|---|---|---|---|
| [#45](https://github.com/f-is-h/Usage4Claude/pull/45) | refactor: extract response models + add SwiftPM test target | 2026-05-13 (`3a960d72`) | First upstream contribution. Two review rounds (rebase + file move to `Models/`). 29 new tests covering `toUsageData()` and `toExtraUsageData()`. |
| [PR #56](https://github.com/f-is-h/Usage4Claude/pull/56) | feat: adopt Sparkle for in-app updates (closes #50) | 2026-06-04 (`242d86b`) | Second upstream contribution. Custom `UpdateChecker` → Sparkle; badge state machine re-wired to `SPUUpdaterDelegate`; App Sandbox XPC entitlements (`mach-lookup` for the Installer/Status services). One review round (f-is-h 2026-05-29) → two fix-up commits `1a7ea48` (polish + badge restore) + `6afd2c8` (sandbox entitlements). Closed proposal #50; the entitlements pattern was proven first in our v1.7.0. |

## Next PR candidates (queue, ordered by readiness)

### 1. Auto-prompt re-login on session expiry  *(M, mid risk — UX feature)*
- Currently upstream surfaces session-expired errors only as text in the popover; user has to navigate to Auth Settings manually.
- Our fork (since v1.2.0) auto-pops the WebLogin window on the first `.sessionExpired` after a previously-valid session, throttled by a `sessionExpiredPrompted` flag that clears on explicit user retry (manual refresh, popover-open fetch).
- Components: `.sessionExpired` `Notification.Name`, posted from `DataRefreshManager.fetchUsage`'s failure branch with throttle check; `MenuBarManager` subscription that calls `WebLoginWindowManager.shared.showLoginWindow()`; `WebLoginWindowManager` itself (already exists upstream for manual login — just needs the trigger).
- ~100 lines but visibly useful. Worth filing an issue first to confirm f-is-h actually wants the auto-prompt UX (he might have deliberately not built it).
- Reference: our v1.2.0 + v1.4.1 commits.

### 2. NDJSON history persistence  *(M, low engineering risk)*
- Replace the per-fetch full-file `usage-history.json` rewrite with NDJSON append (one JSON object per line).
- O(1) per-fetch instead of O(N) rewrite; capped at 10k samples (~7 days at 1-min refresh); compaction on launch when over cap.
- Migration: drain the legacy JSON file on first launch of the new build, dedupe by timestamp, delete legacy.
- File issue first — upstream doesn't have App Group (we moved ours there for widget access), so they'd keep it in `~/Library/Application Support/<bundle>/`. Just a path difference; format stays the same.
- Reference: [`Usage4Claude/Helpers/UsageHistorySample.swift`](../Usage4Claude/Helpers/UsageHistorySample.swift) + [`UsageHistoryStore.swift`](../Usage4Claude/Helpers/UsageHistoryStore.swift) in our fork.

## Proposals to file as issues first (no PR yet)

### 3. Sparkle in-app updates — ✅ **MERGED in PR #56 (2026-06-04)**
- Replaces "manual download → drag to Applications → relaunch" with one-click EdDSA-signed updates.
- Filed as proposal #50 (green-lit 2026-05-24) → implemented in PR #56 → merged 2026-06-04. Done; see the **Merged** table above.
- Pros enumerated: better UX, security via signature verification, removes the ~290-line custom `UpdateChecker`.
- Cons honest about: key management burden, unfix-on-loss of private key.
- PR scope (if green-lit): ~500 lines, mostly deletions of `UpdateChecker` + additions of build-script glue. See issue body for the breakdown.

### 4. Desktop widget  *(L, on their roadmap)*
- Per upstream's README "Long-term Vision": *"More Display Methods → Desktop widgets, Browser extension icon usage display"*.
- Adds: Widget extension target, App Group capability (`group.<theirBundleId>`), shared `UsageSnapshot` + `UsageSnapshotStore`, build-script signing pipeline for the appex, `WidgetCenter.shared.reloadAllTimelines()` calls in the main app's fetch path.
- Worth issue-first to align on: App Group identifier choice, snapshot file format, which widget sizes to ship (we shipped 5 kinds; they may want fewer for initial scope).
- Reference: our fork v1.4.0 (initial widget) + v1.6.0 (sparkline-based widgets).

### 5. Sparkline-in-popover (history visualization)  *(M, depends on #2)*
- Toward their "Data Analysis → Trend charts" long-term vision.
- 14pt-tall sparkline strip under each limit row in `UnifiedLimitRow`, color-matched to the row.
- Reusable `SparklineView` component — pure SwiftUI Path-based, no AppKit, shareable with widget extension if/when #5 lands.
- Depends on #3 (NDJSON history) for efficient read.
- Reference: our fork v1.6.0.

## Smaller candidates discovered later

*(Add here as we notice them in our fork or in their codebase.)*

- [ ] **Cleanup of unused `extra_usage_format` / `extra_usage_remaining` legacy keys** in `Localizable.strings` (5 locales). Dead since the new `extra_usage.usage_amount` / `extra_usage.remaining_amount` keys replaced them. Pure cleanup PR.

- [ ] **OAuth callback server accepts non-loopback peers** — *found 2026-07-10 during the v1.8.0 OAuth port; fixed in our fork, deliberately NOT sent upstream yet.* Upstream `Usage4Claude/Services/CodexOAuth/OAuthCallbackServer.swift` creates its `NWListener` with no `requiredLocalEndpoint`, so it binds the **wildcard** address — during the ~5-minute sign-in window the callback port (1455/1457 for Codex, 1456/1458 for Claude) is reachable from the LAN, not just localhost. The in-code comment claiming it "listens on loopback" is inaccurate. **Severity: low.** Not an auth-code theft vector — the code is delivered to the user's own browser at localhost, and PKCE + a 32-byte `state` nonce gate acceptance, so a LAN peer can neither forge a usable callback nor read the real code. The realistic impact is a narrow-window **denial-of-service**: `didDeliver` latches on the first request carrying `code` or `error` and `handleCallback` fails closed on a `state` mismatch, so any LAN host hitting `/callback?error=x` mid-sign-in aborts that one login (user retries).

  Our fix (in `Services/OAuth/OAuthCallbackServer.swift`, shipped v1.8.0): keep the wildcard bind (needed so a browser resolving `localhost` to either `127.0.0.1` or `::1` connects) and instead drop any non-loopback peer in `handle(_:)` before reading a byte, via `isLoopbackPeer(_:)`. Two traps worth carrying over: on a dual-stack socket an IPv4 peer arrives as an **IPv4-mapped IPv6** address (`::ffff:127.0.0.1`), and Apple's `IPv4Address.isLoopback` matches only `127.0.0.1` — not the whole `127.0.0.0/8` block RFC 1122 reserves (a `127.0.0.53` peer would be wrongly rejected). Verified with a decision-table test over 11 endpoints plus an e2e harness compiling the real source.

  **Decision (2026-07-10, Bryan): hold.** Too small to justify a solo PR round-trip at this severity. Bundle it into the next materially-sized upstream contribution instead. See [UPSTREAM_PORT_AUDIT.md](UPSTREAM_PORT_AUDIT.md) for the full write-up.

- [ ] **`59f4efd` weekly-slot collapse — silent data corruption (MATERIAL; bundle the loopback fix with this).** *Found 2026-08-26 while porting the weeklyModels generalization; the fork deliberately diverges.* Upstream's `59f4efd` folds the two legacy weekly slots into a single `weeklyModels` array by plain `append`, then exposes `opus = weeklyModels.first` / `sonnet = weeklyModels[1]`. An array cannot represent "slot 0 empty, slot 1 filled", so an account with `seven_day_opus: null` (or the `{utilization: 0, resets_at: null}` sentinel) plus a real `seven_day_sonnet` collapses Sonnet into the Opus slot:

  | shape | before `59f4efd` | after |
  |---|---|---|
  | `opus: null`, `sonnet: 67` | `opus=nil, sonnet=67` | **`opus=67, sonnet=nil`** |

  Verified empirically by compiling the pristine and patched files side by side against the same JSON. It is reachable: `toUsageData` has an independent zero-sentinel guard on each slot, upstream has dedicated tests for both, and `getActiveDisplayTypes` checks each slot independently — but no test covers legacy-sonnet-without-legacy-opus, which is why it passes CI. Consequences are silent (no crash, no error): the row reads "Opus Weekly" over Sonnet's number, the menu-bar icon changes shape/colour, the notification is mislabelled, and — worst — anything persisting `data.opus` writes Sonnet's series under Opus. In *this* fork that would permanently corrupt the append-only NDJSON history via `UsageHistorySampleBridge`; upstream has no history store, so their exposure is display-only.

  **Fork's fix (shipped, diverges from upstream):** keep `legacyOpus` / `legacySonnet` as position-fixed stored slots, put only the API-ordered `limits[]` entries in `scopedWeeklyModels`, and make `opus` / `sonnet` computed resolvers (legacy-first, then the next unconsumed scoped model). Regression tests: `testLegacySonnetWithoutOpusKeepsItsOwnSlot`, `testZeroSentinelOpusWithRealSonnetKeepsSlots`.

  **This is the material item that was being waited for** — pair it with the loopback-peer hardening above in one upstream PR.

## Considered and deprioritized

### `fetchOrganizations` → async/await migration (deferred)
- Pure shape change: convert `func fetchOrganizations(sessionKey:completion:)` to `async throws -> [Organization]`.
- Prototyped on branch `migrate-fetch-organizations-async` (deleted), built clean, 29 tests pass.
- Skipped because: zero user-visible change, ~125-line diff for stylistic-only improvement, and post-PR `fetchOrganizations` would be the *only* async public method in a sea of completion-handler ones (`fetchUsage` and `fetchExtraUsage` still completion-handler). One-async-one-handler reads worse than all-handler.
- Would be worth doing as a **bundled** "migrate all three to async/await" PR — ~250-300 lines, cohesive end-state, one review pass. Revisit if upstream signals interest in async-first direction.
- Reference: our [Arcanii fork commit `0e585e4`](https://github.com/arcanii/Usage4Claude-Arcanii/commit/0e585e4) ("Release 1.5.0") has just the `fetchOrganizations` half; we never migrated the other two upstream-side.

## Skipped (not portable, not worth proposing)

- **macOS 26 / Liquid Glass / glass-tube rings / `.glassEffect(in:)`** — Tahoe-only, fork-identity feature.
- **Bundle ID rename** (`com.arcanii.Usage4Claude`) — fork-specific identity.
- **Ring illumination slider** — depends on Tahoe glass APIs.
- **Anglicized code comments** — their convention is Chinese; respect their style.
- **README rewrite for our fork branding** — obviously fork-only.
- **`build.sh` auto-prune of older release dirs + `killall chronod`** — niche to our local-build pipeline.
- **In-app "Reset Widgets" menu item** — depended on Sparkle-style local-update flow; only made sense after #4 + #5 land, and even then mostly a fork-of-fork thing. **Retired from our own fork in v1.7.0** because the hard-reset tier needed subprocess execution (`killall chronod`), blocked under App Sandbox. Definitively not portable.
- **`WidgetReloader` helper** — deleted in our v1.7.0 along with Reset Widgets. Not portable for the same reason.
- **Backported v2.6.1 fixes (cents precision, HTTP/3 disable)** — already in upstream main. N/A.

## Conventions per upstream's CONTRIBUTING.md

- 4-space indentation; PascalCase for types, camelCase for functions/variables.
- Organize code with `// MARK: -` headers.
- Update README / code comments / **all five `Localizable.strings`** for user-visible changes.
- Conventional commit messages (`refactor:`, `fix:`, `feat:`, `chore:`, `docs:`).
- No compile warnings.
- **Match comment language**: upstream uses Chinese comments in most files; keep new code in Chinese where it sits alongside existing Chinese, or English if it's a brand-new file (e.g. our `ClaudeAPIResponseModels.swift` extraction kept the Chinese it inherited from `ClaudeAPIService.swift`).
- Don't add AI co-author trailers (`Co-Authored-By: Claude …`) to upstream commits — keep commits clean of attribution that may distract from review.

## Workflow

```bash
# Fork repo: ~/Desktop/github_repos/Usage4Claude-fork/
cd ~/Desktop/github_repos/Usage4Claude-fork

# Always start a new PR branch off upstream/main
git fetch upstream
git checkout upstream/main
git checkout -b <descriptive-branch-name>

# ... make changes ...

# Test:
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Usage4Claude.xcodeproj \
    -scheme Usage4Claude -configuration Debug \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build

# Push (must be done in your own Terminal — interactive credential prompt):
git push -u origin <branch>

# Then open PR via web: https://github.com/f-is-h/Usage4Claude/compare/main...arcanii:Usage4Claude-fork:<branch>
```
