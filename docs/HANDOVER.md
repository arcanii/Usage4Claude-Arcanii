# U4Claude (Arcanii Mod) — Session Handover

If you're picking this project up cold, read this first. It's the orientation guide that points at the rest of the docs and warns about non-obvious gotchas.

## What this is

A macOS menu bar app that polls the **private** `claude.ai/api/organizations/<id>/usage` endpoint and renders the user's 5-hour, 7-day, Opus, Sonnet, and Extra Usage limits as compact rings/numbers in the menu bar. Authentication is by session cookie scraped from a logged-in `WKWebView` — **not** the official Anthropic API, and not an API key. Cloudflare bypass is achieved by spoofing Chrome browser headers.

- **Bundle id:** `com.arcanii.Usage4Claude`
- **Product name:** `U4Claude.app` (renamed from upstream's `Usage4Claude.app` so both can coexist)
- **macOS deployment target:** **26.0** (Tahoe). Bumped from 13.0 in v1.4.0. We use the macOS 26 Liquid Glass APIs unconditionally.
- **App Sandbox:** **on** for both main app and widget since v1.7.0. Sparkle's bundled XPC services handle update install under sandbox. See the sandbox gotchas section below.
- **Universal binary** (x86_64 + arm64).
- **Current version:** v1.7.0 (2026-05-29) — see [RELEASES/](RELEASES/).

## Where we are right now (read if you're resuming a session)

- **v1.7.0 shipped 2026-05-29.** First sandboxed release of the Arcanii fork. Bryan installed locally and reported "no issues so far" — we asked him to spot-check the `[SandboxBootstrap]` log line in Console.app and verify the widget still ticks. No further reports in.
- **Upstream PR #56 is open and got a substantive review from f-is-h on 2026-05-29.** Review at <https://github.com/f-is-h/Usage4Claude/pull/56>. Five items:
  1. **Blocker — App Sandbox.** Upstream ships `ENABLE_APP_SANDBOX = YES` with no entitlements file. Our PR would build clean and fail on install. f-is-h wants Sparkle's sandboxed XPC flow. **Our v1.7.0 is the proof-of-concept for this**; the entitlements + Info.plist pattern is now battle-tested and ready to drop into the upstream tree.
  2. **Restore the rainbow update badge.** Wire `SPUUpdaterDelegate.updater(_:didFindValidUpdate:)` → `hasAvailableUpdate = true` so the existing badge state machine lights up alongside Sparkle's modal. Repoint `simulateUpdateAvailable` at the new state. Un-delete `MenuBarUI.createRainbowText` + `createBadgeIcon` + `MenuBarIconRenderer.addBadgeToImage` + the `hasUpdate` parameter chain (currently deleted in the PR).
  3. **Markdown release notes in appcast.** Switch `<description>` template to `sparkle:format="markdown"` (Sparkle 2.9 supports natively) so we can paste from CHANGELOG.md without an HTML parallel.
  4. **Docs filename mismatch.** `docs/RELEASING.md` referenced in 3 places (Info.plist, build.sh, appcast.xml) but actual file is `docs/SPARKLE_SETUP.md`. Rename references to match.
  5. **Dead code scrub.** Orphaned `L.Update.*` localization keys (`LocalizationHelper.swift:181-211` + `.xcstrings`); the `notificationMessage` writer in `MenuBarManager`; rainbow banner at `UsageDetailView.swift:540-558`. Most of these get reused once #2 lands; the orphaned localization keys should be cleanly removed.
  6. **README pass.** Intro + features sections still describe the manual DMG drag and the badge/rainbow as if untouched.
- **Agreed slicing** (decided 2026-05-29): two fix-up pushes to `sparkle-in-app-updates` on `~/Desktop/github_repos/Usage4Claude-fork/`.
  - **Push 1 (polish):** rainbow badge restore + Markdown appcast + RELEASING.md rename + dead code scrub + README pass. Low risk, mechanical given the scope.
  - **Push 2 (sandbox):** entitlements file + `SUEnableInstallerLauncherService` Info.plist key + `ENABLE_APP_SANDBOX = YES` pbxproj flip. Mirror what shipped in our v1.7.0.
  - Both go into the same PR; f-is-h explicitly offered to split sandbox into a follow-up if it helped, but they're cohesive enough that one PR keeps the review story clean.
- **Queued tasks:** TaskList entries #17 (sandbox backport) and #18 (polish items). The task list also includes the v1.6.4 and v1.7.0 release tasks (all completed) for archaeological reference.
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
│                                   App Group + Sparkle XPC mach-lookup; v1.7.0+)
├── Tests/Usage4ClaudeCoreTests/   SwiftPM XCTest suite (50 tests: SemverCompare,
│                                   UsageResponse, ExtraUsageResponse)
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

Currently 50 tests across `SemverCompareTests.swift`, `UsageResponseTests.swift`, and `ExtraUsageResponseTests.swift`. The test target is a SwiftPM package that lives alongside the `.xcodeproj`; it cherry-picks pure-function source files (`SemverCompare.swift`, `ClaudeAPIResponseModels.swift`) from `Usage4Claude/Helpers/`. To extend coverage, extract additional dependency-free helpers into `Usage4Claude/Helpers/` and add them to `Package.swift`'s `Usage4ClaudeCore` target's `sources` array. Anything that touches `L.*`, `UserSettings`, or `Logger` should stay in a sibling `+Formatting`-style file (see `UsageData+Formatting.swift`) so the test target doesn't have to drag in those dependencies.

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
