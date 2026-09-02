# U4Claude (Arcanii Mod) — Session Handover

If you're picking this project up cold, read this first. It's the orientation guide that points at the rest of the docs and warns about non-obvious gotchas.

## What this is

A macOS menu bar app that renders the user's 5-hour, 7-day, weekly per-model (Opus / Sonnet / Fable — named by the API) and Extra Usage limits as compact rings/numbers in the menu bar. **Two auth paths since v1.8.0:**
  - **OAuth (default).** "Sign in with Claude" runs the Claude Code public OAuth client (PKCE) in the system browser; usage comes from `api.anthropic.com/api/oauth/usage` with a Bearer token. **No cookie, no Cloudflare header spoofing on this path.**
  - **Legacy session key.** Polls the **private** `claude.ai/api/organizations/<id>/usage` endpoint with a cookie scraped from a logged-in `WKWebView`, using spoofed Chrome headers to get past Cloudflare. Still supported; still the path the spoofed UA and `accept-language` header matter for.

  Neither path is the official/documented Anthropic API, and neither uses an API key.

- **Bundle id:** `com.arcanii.Usage4Claude`
- **Product name:** `U4Claude.app` (renamed from upstream's `Usage4Claude.app` so both can coexist)
- **macOS deployment target:** **26.0** (Tahoe). Bumped from 13.0 in v1.4.0. We use the macOS 26 Liquid Glass APIs unconditionally.
- **App Sandbox:** **on** for both main app and widget since v1.7.0. Sparkle's bundled XPC services handle update install under sandbox. See the sandbox gotchas section below.
- **Universal binary** (x86_64 + arm64).
- **Current version:** v1.9.2 (2026-08-26) — see [RELEASES/](RELEASES/).

## Where we are right now (read if you're resuming a session)

- **v1.9.0 shipped 2026-08-26.** Feature + hardening release built from the upstream **v3.3.0** delta audit (see [UPSTREAM_PORT_AUDIT.md](UPSTREAM_PORT_AUDIT.md)). Headline: **weekly per-model limits are read and named correctly**. Confirmed live on Bryan's account 2026-08-26 that Claude's API now returns `seven_day_opus`/`seven_day_sonnet` as **null** and reports the weekly per-model limit in `limits[]` as `{kind:"weekly_scoped", scope:{model:{display_name:"Fable"}}}` — so v1.8.0 was silently showing **no weekly model row at all**. `UsageData` now keeps `legacyOpus`/`legacySonnet` as position-fixed slots with the API-ordered entries in `scopedWeeklyModels`, and `opus`/`sonnet`/`overflowWeeklyModels` are computed resolvers; rows label from the model name and a 3rd+ model renders its own row. **This deliberately diverges from upstream `59f4efd`**, which folds both slots into one array and promotes Sonnet into the Opus slot when Opus is absent — silent corruption here because `UsageHistorySampleBridge` writes `data.opus` into the append-only NDJSON history. Also in this release: foreground notifications actually deliver (`UNUserNotificationCenterDelegate` was missing entirely), OAuth manual-paste fallback (upstream #68), OAuth 401 self-heal, callback `didDeliver` reset, **PKCE `SecRandomCopyBytes` status check** (security), `accept-language` from the system locale instead of hardcoded `zh-CN`, `TimerManager` scheduling on the main run loop, `MenuBarManager` sinks hopping to main, `saveAccounts` snapshot, unified `customDisplayTypes` default, and CI heredoc-injection hardening. 63 tests (+8). `UsageData` is in-memory only, so no persisted shape changed — no widget/history migration, **no re-login**. Tag `v1.9.0`; release commit `afd5e9e` + appcast enclosure `237d54f`. **Verified end to end** (Bryan, 2026-08-26): notarized + stapled DMG, DMG byte length matched the Sparkle enclosure, live appcast served `v1.9.0`/build 19, the in-app **1.8.0 → 1.9.0 Sparkle upgrade installed cleanly with no re-login**, and the popover now shows the **Fable** weekly row that v1.8.0 was silently omitting.

- **v1.9.1 shipped 2026-08-26.** Patch release, bug fixes only. (a) **Widget weekly tiles now use the real model name** — v1.9.0 fixed the popover but the widget target still hardcoded `"Opus"`/`"Sonnet"`, so the same Fable number showed under two different names. `UsageSnapshot` gained optional `opusModelName`/`sonnetModelName`, populated by `UsageSnapshotBridge` and used by `LargeDashboardWidget`/`ExtraLargeWidget` with the old strings as fallback; the fields are **Optional and additive on purpose** because the widget may read a snapshot written by the older app mid-update. `UsageSnapshot.swift` joined the SwiftPM test target with legacy-decode and round-trip guards. (b) **Per-account notifications** — switching accounts fired a false "limit reset" (usage was compared against the previous fetch even when it belonged to another account; note the 30-point-drop path needs previous >= 90%, so the real trigger was the `resetsAt`-changed path, which has no floor) and swallowed warnings (dedup keyed on `LimitType.rawValue` alone). Dedup is now keyed `"<accountId>:<limitType>"`, `DataRefreshManager.prepareForAccountSwitch()` skips one comparison after a switch, and the never-called `resetAllNotificationStates()` was replaced by `resetNotificationStates(forAccountId:)` wired into `removeAccount`. Also untracked `.claude/scheduled_tasks.lock`. 65 tests. Tag `v1.9.1`, single release commit `f484319` (build.sh ran *before* the commit, so the appcast enclosure landed in the same commit — no follow-up needed, unlike v1.8.0/v1.9.0). **Verified**: notarized + stapled, DMG byte length matched the enclosure, live appcast served v1.9.1/build 20, and the **in-app 1.9.0 → 1.9.1 Sparkle upgrade completed** (Bryan, 2026-08-26). Note the widget label only changes after the updated app's next fetch rewrites the App Group snapshot.

- **v1.8.0 shipped 2026-07-10.** Feature release, five upstream ports + hardening + localization fixes. Headline: **system-browser OAuth (PKCE) sign-in** ("Sign in with Claude" opens the default browser instead of an embedded `WKWebView` — unblocks Google / Microsoft / enterprise SSO / passkey; closes upstream #49). OAuth accounts read usage via `/api/oauth/usage` with a Bearer token and **skip the Cloudflare header path entirely**; legacy session-key accounts are unchanged and keep the embedded WebLogin as a fallback. Also: custom-display "menu bar only" toggle; Extra Usage decode fix (fractional `used_credits` no longer drops the row, +2 tests); 403-during-org-fetch now reports session-expired not Cloudflare-blocked; localized the HTTP-error text and the auth-error "Go to Settings" button (were English/zh-Hans only). New `com.apple.security.network.server` entitlement for the OAuth loopback callback listener, which **accepts loopback peers only** (LAN-DoS hardening — see below). Full audit + live smoke test in [UPSTREAM_PORT_AUDIT.md](UPSTREAM_PORT_AUDIT.md). Tag `v1.8.0`; release commit `428cbd1` + appcast enclosure `5b09347`. **Verified on a real v1.7.x → v1.8.0 Sparkle install** (Bryan, 2026-07-10) — fetched, downloaded, one-click-installed, no re-login. Release-process note: the first publish attempt half-failed because a pasted command block with inline `#` comments got mangled by Bryan's zsh (no `interactive_comments`) — `build.sh` never ran but `git push`/tag did; recovered cleanly with a follow-up appcast commit (no force-push). Hand him commands one-per-line, no inline comments.
  - **OAuth callback hardening — backlogged, do NOT open a solo PR.** `Services/OAuth/OAuthCallbackServer.swift` binds the wildcard address, so during the ~5-min sign-in window the callback port is LAN-reachable. Fixed in the fork (drop non-loopback peers before reading a byte, via `isLoopbackPeer` handling `::ffff:` mapping + full `127/8`). Upstream `f-is-h`'s `CodexOAuth/OAuthCallbackServer.swift` is identically affected. **Severity is low** — not a credential/auth-code theft vector (PKCE + 32-byte `state` gate acceptance; the code goes to the user's own browser), only a narrow-window LAN denial-of-service that aborts a single sign-in (user retries). **Decision 2026-07-10 (Bryan): hold** — too small to justify a PR round-trip; bundle it into the next materially-sized upstream contribution. Tracked under "Smaller candidates discovered later" in [UPSTREAM_CONTRIBUTIONS.md](UPSTREAM_CONTRIBUTIONS.md).

- **v1.7.1 shipped 2026-06-02.** Small maintenance release: Extra Usage currency-symbol localization (renders the account's billing currency; +KRW for the Korean locale) + spoofed Chrome UA 148→149. First release cut *after* the v1.7.0 sandbox flip, so it doubled as an end-to-end test of the post-sandbox Sparkle pipeline (build → notarize → staple → EdDSA-sign → appcast → live `200` download) — all green — and then **verified on a real v1.7.0 → v1.7.1 install**: Sparkle fetched, downloaded, and one-click-installed cleanly with **no re-login**, confirming the post-sandbox in-app-update path works (the open question from v1.7.0's "ship and watch"). Tag `v1.7.1`, release commit `b35cf8b`; backlog #1 now shipped.

- **PR #56 MERGED upstream 2026-06-04 by f-is-h 🎉** (merge commit `242d86b`; proposal #50 closed). The Sparkle adoption — custom `UpdateChecker` → Sparkle, badge state machine re-wired to `SPUUpdaterDelegate`, App Sandbox XPC entitlements — is now in `f-is-h/Usage4Claude` main. The detailed review punch-list + slicing further down are now **historical**. Two commits on `sparkle-in-app-updates` (in `~/Desktop/github_repos/Usage4Claude-fork/`): `1a7ea48` (badge restore + polish, review items 2–6) and `6afd2c8` (Sparkle XPC `mach-lookup` entitlements for the already-on sandbox, item 1). Debug build clean, 29 tests pass, no new warnings, no AI co-author trailers; pushed to `origin`, and a slicing-recap comment mapping commits→review-items is on the PR ([issuecomment-4581272906](https://github.com/f-is-h/Usage4Claude/pull/56#issuecomment-4581272906)). PR body reframed + trimmed by Bryan 2026-05-30 (dropped the standalone "App Sandbox" and Sparkle-release-mirror points). **Merged — nothing left to do on the PR.** (The "draft replies for Bryan, don't post to the PR directly" rule still stands for any future upstream PRs — see the gotcha below.) Code-truth notes that bit during the work: the badge helpers (`createRainbowText`/`createBadgeIcon`/`addBadgeToImage`) were never deleted by the PR — only their call sites — so restoring was re-wiring, not un-deletion; `L.Update.okButton` was kept (reused generically by diagnostics); upstream ships **6** locales as `.strings` (not 5 / `.xcstrings`); the entitlements omit the App Group (upstream has no widget), and `network.client` was already granted via `ENABLE_OUTGOING_NETWORK_CONNECTIONS`, so the lone real sandbox blocker was the Sparkle mach-lookup exception.

- **v1.7.0 shipped 2026-05-29.** First sandboxed release of the Arcanii fork. Bryan installed locally and reported "no issues so far" — we asked him to spot-check the `[SandboxBootstrap]` log line in Console.app and verify the widget still ticks. No further reports in.
- **[Historical — PR #56 merged 2026-06-04.] Upstream PR #56 got a substantive review from f-is-h on 2026-05-29.** Review at <https://github.com/f-is-h/Usage4Claude/pull/56>. Five items:
  1. **Blocker — App Sandbox.** Upstream ships `ENABLE_APP_SANDBOX = YES` with no entitlements file. Our PR would build clean and fail on install. f-is-h wants Sparkle's sandboxed XPC flow. **Our v1.7.0 is the proof-of-concept for this**; the entitlements + Info.plist pattern is now battle-tested and ready to drop into the upstream tree.
  2. **Restore the rainbow update badge.** Wire `SPUUpdaterDelegate.updater(_:didFindValidUpdate:)` → `hasAvailableUpdate = true` so the existing badge state machine lights up alongside Sparkle's modal. Repoint `simulateUpdateAvailable` at the new state. Un-delete `MenuBarUI.createRainbowText` + `createBadgeIcon` + `MenuBarIconRenderer.addBadgeToImage` + the `hasUpdate` parameter chain (currently deleted in the PR).
  3. **Markdown release notes in appcast.** Switch `<description>` template to `sparkle:format="markdown"` (Sparkle 2.9 supports natively) so we can paste from CHANGELOG.md without an HTML parallel.
  4. **Docs filename mismatch.** `docs/RELEASING.md` referenced in 3 places (Info.plist, build.sh, appcast.xml) but actual file is `docs/SPARKLE_SETUP.md`. Rename references to match.
  5. **Dead code scrub.** Orphaned `L.Update.*` localization keys (`LocalizationHelper.swift:181-211` + `.xcstrings`); the `notificationMessage` writer in `MenuBarManager`; rainbow banner at `UsageDetailView.swift:540-558`. Most of these get reused once #2 lands; the orphaned localization keys should be cleanly removed.
  6. **README pass.** Intro + features sections still describe the manual DMG drag and the badge/rainbow as if untouched.
- **Slicing — shipped 2026-05-30** (decided 2026-05-29): two commits on `sparkle-in-app-updates` in `~/Desktop/github_repos/Usage4Claude-fork/`.
  - ✅ **Push 1 (polish) — `1a7ea48`:** rainbow badge restore (re-wired to Sparkle's `SPUUpdaterDelegate`) + Markdown appcast + RELEASING→SPARKLE_SETUP rename + dead-code scrub + README pass.
  - ✅ **Push 2 (Sparkle XPC entitlements) — `6afd2c8`:** new `Config/Usage4Claude.entitlements` (app-sandbox + network.client + Sparkle XPC mach-lookup) wired via `CODE_SIGN_ENTITLEMENTS`, plus the `SUEnableInstallerLauncherService` Info.plist key. (Upstream already had `ENABLE_APP_SANDBOX = YES`, so no pbxproj flip; adapted from our v1.7.0 by dropping the App Group — upstream has no widget.)
  - Both went into the one PR as separate commits; the PR comment offers to split the sandbox commit into a follow-up if f-is-h would rather land the polish first.
- **Queued tasks:** done — the sandbox backport and polish items shipped in the two commits above. (The session TaskList doesn't persist across sessions, so the prior `#17` / `#18` references no longer resolve.)
- **No verification gate.** Bryan classified the user base as "experimental, ship and watch" — no local test rig for cross-sandbox-state Sparkle updates is required before pushing to upstream either.

## Read these next, in order

1. **[ARCANII_DESIGN.md](ARCANII_DESIGN.md)** — module map, data flow, error mapping table. The "what's where" reference.
2. **[ARCANII_BACKLOG.md](ARCANII_BACKLOG.md)** — open follow-ups with effort tags. All P0/P1/P2/P3 items have shipped.
3. **[UPSTREAM_CONTRIBUTIONS.md](UPSTREAM_CONTRIBUTIONS.md)** — log of what we've proposed (or plan to propose) back to f-is-h's repo. Companion to the backlog but upstream-facing.
4. **[RELEASES/](RELEASES/)** — per-version release notes. v1.0.0 (initial fork) through v1.7.0 (App Sandbox + Sparkle XPC).
5. **[WIDGET_SETUP.md](WIDGET_SETUP.md)** — kept around in case the widget target ever needs to be rebuilt; unused for everyday work.

## Repo layout

```
Usage4Claude-Arcanii/
├── Usage4Claude/                  Main app source (synchronized Xcode group)
│   ├── App/                       Entry point + menu bar plumbing
│   ├── Helpers/                   DataRefreshManager, UsageHistoryStore,
│   │                              UsageSnapshot{,Bridge}, SemverCompare, …
│   ├── Models/                    UserSettings (split across +Accounts,
│   │                              +LaunchAtLogin, +SmartMode extensions)
│   ├── Services/                  ClaudeAPIService, ClaudeAPIHeaderBuilder,
│   │                              KeychainManager, NotificationManager
│   ├── Views/                     SwiftUI: SettingsView, UsageDetailView,
│   │                              WebLogin*, DiagnosticsView
│   └── Resources/                 Localizable.strings (en, zh-Hans, zh-Hant, ja, ko)
├── Usage4ClaudeWidget/            Widget extension (synchronized group)
│   ├── Usage4ClaudeWidget.swift   Widget + TimelineProvider + small/medium views
│   ├── Usage4ClaudeWidgetBundle.swift  @main entry point
│   ├── Info.plist                 NSExtensionPointIdentifier = widgetkit-extension
│   └── Usage4ClaudeWidget.entitlements  sandbox + App Group + no network
├── Config/
│   ├── Info.plist                 Static main-app Info.plist with Sparkle SU* keys
│   └── Usage4Claude.entitlements  Main-app entitlements (sandbox on + network.client +
│                                   network.server (OAuth loopback callback; v1.8.0) +
│                                   App Group + Sparkle XPC mach-lookup; v1.7.0+)
├── Tests/Usage4ClaudeCoreTests/   SwiftPM XCTest suite (65 tests: SemverCompare,
│                                   UsageResponse, ExtraUsageResponse, UsageHistoryFileStore)
├── Package.swift                  Standalone SwiftPM package for `swift test`
├── docs/                          Design, backlog, release notes (per above)
├── scripts/
│   ├── build.sh                   Archive → Export → DMG → Notarize → Staple → sign_update
│   ├── build.config.example       Template for per-developer Developer ID + notary profile
│   └── inject-sparkle-keys.sh     (deleted; logic now inline in pbxproj build phase)
├── appcast.xml                    Sparkle feed served via raw.githubusercontent.com
└── Usage4Claude.xcodeproj         The build is here. Don't edit pbxproj by hand
                                   for new TARGETS — see warnings below.
```

## How to build

```bash
# Just compile (Debug, no notarize)
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
    xcodebuild -project Usage4Claude.xcodeproj -scheme Usage4Claude \
    -configuration Debug -allowProvisioningUpdates build

# Full release pipeline (Release, signed, notarized, stapled, Sparkle-signed)
./scripts/build.sh
```

`./scripts/build.sh` produces `build/Usage4Claude-Release-<version>/U4Claude-v<version>.dmg`. It also prints a copy-pasteable `<enclosure>` line for `appcast.xml` after Sparkle signing.

`xcode-select` on this machine points at CommandLineTools, so the build script forces `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. Direct `xcodebuild` invocations need the same.

## How to test

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

Currently 65 tests across `SemverCompareTests.swift`, `UsageResponseTests.swift`, `ExtraUsageResponseTests.swift`, and `UsageHistoryFileStoreTests.swift`. The test target is a SwiftPM package that lives alongside the `.xcodeproj`; it cherry-picks pure-function source files (`SemverCompare.swift`, `ClaudeAPIResponseModels.swift`) from `Usage4Claude/Helpers/`. To extend coverage, extract additional dependency-free helpers into `Usage4Claude/Helpers/` and add them to `Package.swift`'s `Usage4ClaudeCore` target's `sources` array. Anything that touches `L.*`, `UserSettings`, or `Logger` should stay in a sibling `+Formatting`-style file (see `UsageData+Formatting.swift`) so the test target doesn't have to drag in those dependencies.

## Releasing

The full ship checklist:

1. Bump `MARKETING_VERSION` (e.g. 1.4.0 → 1.5.0) and `CURRENT_PROJECT_VERSION` (e.g. 7 → 8) in **all four** target configs in `Usage4Claude.xcodeproj/project.pbxproj` (main Debug + main Release + widget Debug + widget Release). Yes, the widget's project version should match the main app's.
2. `./scripts/build.sh` — produces signed/notarized/stapled DMG + prints the appcast `<enclosure>` line.
3. Paste the `<enclosure>` line into a new top-of-list `<item>` in `appcast.xml`. Update `<title>`, `<pubDate>`, `<sparkle:version>`, `<sparkle:shortVersionString>`, `<link>`, and `<description>` (CDATA HTML).
4. Write `docs/RELEASES/v<version>.md` with user-facing notes.
5. Commit + push.
6. `git tag -a v<version> -m "U4Claude v<version>" && git push origin v<version>`.
7. `gh release create v<version> build/Usage4Claude-Release-<version>/U4Claude-v<version>.dmg --title "U4Claude v<version>" --notes-file docs/RELEASES/v<version>.md`.

After step 7, existing v1.3.2+ users get the prompt via Sparkle within 24 h.

## Critical secrets — back these up

- **Sparkle EdDSA private signing key.** Stored in your **login keychain** under `https://sparkle-project.org` (managed by `generate_keys`, never written to disk in plain text). Public key embedded in the app's Info.plist as `SUPublicEDKey = hGTiB0kyn45HOB8WWKdAHc28+Bthe8Rv8O7asa4nG2c=`. **If you lose this key, every existing v1.3.0+ install becomes orphaned** — they'll reject all future signed updates. Export to a `.p12` and store somewhere safe (1Password, encrypted backup).
- **`xcrun notarytool` keychain profile** named `Usage4Claude-Arcanii-notarize`. App-specific password generated at `appleid.apple.com` for the Apple ID associated with team `386M76FV3K`. If lost, regenerate and run `xcrun notarytool store-credentials Usage4Claude-Arcanii-notarize --apple-id <id> --team-id 386M76FV3K --password <new-password>`.
- **Apple Developer ID Application certificate** (team `386M76FV3K`). Already in keychain; back up to `.p12` if not previously done.

## Non-obvious gotchas

### Upstream PR comments are Bryan's to post

When working an upstream PR (e.g. #56), **draft** comments and replies for Bryan and let **him post them after his own review** — do **not** post to the PR directly. (This session posted the slicing-recap comment straight to #56 before that was set; it's been left up.) Pushing branch *commits* is fine when he's asked for it; it's PR *comments / replies* that route through Bryan.

### TCC restrictions on `~/Desktop/github_repos`

This repo lives in `~/Desktop/github_repos/Usage4Claude-Arcanii`, which on macOS Sequoia+ is a TCC-protected location. Two known consequences:

- **`create-dmg` fails** if the volume name collides with a recent mount — use unique volume names per build (the script appends `-${VERSION}`).
- **Run-script build phases that exec scripts under this directory fail** with "Operation not permitted" (we hit this trying to inline a `scripts/inject-sparkle-keys.sh`). Bash code that needs to run during build is inlined directly in the pbxproj build phase's `shellScript` instead of called via a path under the repo.

### Static `Info.plist`, not auto-generated

Both the main app and widget use **static** `Info.plist` files (`Config/Info.plist` and `Usage4ClaudeWidget/Info.plist`), with `GENERATE_INFOPLIST_FILE = NO`. The auto-generated path silently drops third-party keys like `SUFeedURL`, `SUPublicEDKey`, `SUEnableAutomaticChecks` (only Apple-known keys survive `INFOPLIST_KEY_*`). When adding new keys for Sparkle / App Groups / similar, add them to the static plist.

### Manual signing + App Group + new bundle id is incompatible

`scripts/build.sh` uses **automatic signing** (with `-allowProvisioningUpdates`) for both targets. Earlier versions used manual signing with `CODE_SIGN_STYLE=Manual` + `Developer ID Application`, but adding the App Group entitlement broke that — App Groups + Manual style requires a pre-issued provisioning profile per bundle id, and the script wasn't going to pre-issue them. Automatic + provisioning-updates lets Xcode manage profiles transparently, and the export step (`method = developer-id` in `ExportOptions.plist`) re-signs to Developer ID Application for distribution.

### Adding a new Xcode TARGET — don't hand-edit pbxproj

The widget extension target was originally attempted via hand-rolled pbxproj surgery. It worked at the build-graph level but always failed at signing because Apple's automatic-signing dance needs to register the new bundle id with the developer portal, which is gated on interactive Apple-ID auth in Xcode → Preferences → Accounts. Adding new targets is much more reliable through **File → New → Target** in Xcode UI, then reconciling the generated source/plist/entitlements files with what's already in the repo. See [WIDGET_SETUP.md](WIDGET_SETUP.md) for the dance done for the widget — same pattern works for any future extension.

### `UsageSnapshot.swift` is shared across targets

`Usage4Claude/Helpers/UsageSnapshot.swift` is a member of **both** the main app target (via the `Usage4Claude/` synchronized group) and the widget extension target (added via Xcode UI's File Inspector → Target Membership → check `Usage4ClaudeWidgetExtension`). If you move/rename it, update the widget's target-membership manually.

### App Group container path

Both main app (sandbox-on since v1.7.0) and widget (sandbox-on) read/write to:
```
~/Library/Group Containers/group.com.arcanii.Usage4Claude/usage-snapshot.json
```
The main app writes on each successful `fetchUsage`; the widget reads on each timeline tick. `WidgetCenter.shared.reloadAllTimelines()` from the main app's success path nudges the widget for an immediate refresh.

### App Sandbox + Sparkle XPC (v1.7.0+)

The main app's `Config/Usage4Claude.entitlements` requires four things to be in lockstep — drop any one and either the sandbox refuses to launch, network calls fail, or Sparkle's installer can't reach `/Applications`:

- `com.apple.security.app-sandbox = true`
- `com.apple.security.network.client = true` (HTTPS to claude.ai + raw.githubusercontent.com)
- `com.apple.security.application-groups` array containing `group.com.arcanii.Usage4Claude` (shared with the widget)
- `com.apple.security.temporary-exception.mach-lookup.global-name` array with `$(PRODUCT_BUNDLE_IDENTIFIER)-spks` and `$(PRODUCT_BUNDLE_IDENTIFIER)-spki` — these are Sparkle's Installer and Status XPC services bundled inside the Sparkle framework. Variable substitution is performed by Xcode at build time.

`Config/Info.plist` also needs `SUEnableInstallerLauncherService = true`. `SUEnableDownloaderService` is deliberately omitted — Sparkle's [sandboxing guide](https://sparkle-project.org/documentation/sandboxing/) says the Downloader XPC is only needed when the main app *lacks* `network.client`, which we have.

The SwiftPM Sparkle dependency bundles `Installer.xpc` + `Downloader.xpc` into the .app automatically — no pbxproj surgery required, no explicit framework embedding step. The DMG grows from ~6.9 MB (v1.6.4) to ~7.9 MB because of these services.

### Sandbox transition bootstrap

`UserSettings.init()` has a block at the very top, guarded by a one-shot `sandboxBootstrapped_v1.7` UserDefaults flag, that logs the first-sandboxed-launch event with presence checks for the major settings keys. **It does NOT migrate UserDefaults itself** — `cfprefsd` handles the carry-over from `~/Library/Preferences/com.arcanii.Usage4Claude.plist` to the container path transparently for same-bundle-ID transitions.

Reading the legacy plist directly from inside the sandbox would need `com.apple.security.temporary-exception.files.absolute-path.read-only` for that file. We deliberately don't take on that entitlement — `cfprefsd` is reliable in practice for our migration pattern, and the entitlement would be permanent debt for a one-time concern.

If a user reports settings reset after the v1.7.0 update, the `[SandboxBootstrap]` log line in Console.app shows which keys were absent at first launch, which tells us whether `cfprefsd` dropped the migration. The fallback is "reconfigure once" — we live with it.

**Keychain items are NOT migrated** under sandbox transitions because the access group changes. Existing v1.3.0+ users re-pair via Auth Settings → Browser Login on first launch of v1.7.0+. This is documented in the release notes and is the price we paid for sandbox-on.

## Quick context for the most-likely next tasks

- **Adding a new Settings field?** It's a `@Published` on `UserSettings`, persisted to `UserDefaults` in the `didSet`, restored in `init()`, and rendered in `Views/Settings/Tabs/GeneralSettingsView.swift` (or split if it belongs to its own concern — see the existing `+Accounts` / `+LaunchAtLogin` / `+SmartMode` extensions for the pattern).
- **Changing the popover UI?** `Views/UsageDetailView.swift`. The ring rendering with the glass-tube gradient + `.shadow` glow + `.glassEffect(in:)` is around the `if refreshState.isRefreshing` branches.
- **Tweaking smart-mode refresh timing?** `Models/UserSettings+SmartMode.swift` — the active → idleShort → idleMedium → idleLong tier transitions and tick counts.
- **Debugging an API failure?** `Services/ClaudeAPIService.swift`. The error mapping table is at the top of [ARCANII_DESIGN.md](ARCANII_DESIGN.md). 403 with `permission_error` body → `.sessionExpired` (auto-prompts re-login); 403 without that body or with HTML response → `.cloudflareBlocked`.
- **User reports "settings reset" after the v1.7.0 update?** Open `Console.app`, filter on the `U4Claude` subsystem, look for the `[SandboxBootstrap]` notice at first sandboxed launch. The three presence flags (`iconDisplayMode`, `displayMode`, `smartModeTier`) tell you which keys `cfprefsd` failed to carry over. The migrator deliberately doesn't try to fix it — see the "Sandbox transition bootstrap" gotcha for why.
- **User reports "session expired" on v1.7.0?** That's expected behavior — see release notes. Auth Settings → Browser Login fixes it in one click. Not a bug unless they're seeing it repeatedly after re-pairing.

## Pinned versions

- Sparkle: `2.9.1` (pinned in `Usage4Claude.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`)
- Spoofed Chrome user-agent: `148.0.0.0` (in `ClaudeAPIHeaderBuilder.swift`)
- Tools required on the build machine: `xcodebuild` (Xcode 26.0+), `create-dmg` (`brew install create-dmg`), Sparkle's `sign_update` (download from sparkle-project releases; default location `/tmp/sparkle-tools/bin/sign_update`, override via `SIGN_UPDATE` env var)
