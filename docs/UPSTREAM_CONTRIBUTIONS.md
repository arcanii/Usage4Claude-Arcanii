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
| [issue #50](https://github.com/f-is-h/Usage4Claude/issues/50) | Proposal: adopt Sparkle for in-app updates | Proposal | **Open, awaiting f-is-h** | 2026-05-13: filed as a discussion-not-PR. Three-way decision request: yes / "key burden too much" / not now. |

## Merged

| # | Title | Merged | Notes |
|---|---|---|---|
| [#45](https://github.com/f-is-h/Usage4Claude/pull/45) | refactor: extract response models + add SwiftPM test target | 2026-05-13 (`3a960d72`) | First upstream contribution. Two review rounds (rebase + file move to `Models/`). 29 new tests covering `toUsageData()` and `toExtraUsageData()`. |

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

### 3. Sparkle in-app updates  *(L, high decision-cost)* — **issue #50 filed**
- Replaces "manual download → drag to Applications → relaunch" with one-click EdDSA-signed updates.
- Filed as proposal-not-PR at [f-is-h/Usage4Claude#50](https://github.com/f-is-h/Usage4Claude/issues/50). Awaiting decision.
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
- **In-app "Reset Widgets" menu item** — depends on Sparkle-style local-update flow; only makes sense after #4 + #5 land, and even then it's mostly a fork-of-fork thing.
- **`WidgetReloader` helper** — same dependency on widget + chronod-recovery flow.
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
