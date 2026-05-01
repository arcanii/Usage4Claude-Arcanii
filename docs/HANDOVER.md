# U4Claude (Arcanii Mod) — Session Handover

If you're picking this project up cold, read this first. It's the orientation guide that points at the rest of the docs and warns about non-obvious gotchas.

## What this is

A macOS menu bar app that polls the **private** `claude.ai/api/organizations/<id>/usage` endpoint and renders the user's 5-hour, 7-day, Opus, Sonnet, and Extra Usage limits as compact rings/numbers in the menu bar. Authentication is by session cookie scraped from a logged-in `WKWebView` — **not** the official Anthropic API, and not an API key. Cloudflare bypass is achieved by spoofing Chrome browser headers.

- **Bundle id:** `com.arcanii.Usage4Claude`
- **Product name:** `U4Claude.app` (renamed from upstream's `Usage4Claude.app` so both can coexist)
- **macOS deployment target:** **26.0** (Tahoe). Bumped from 13.0 in v1.4.0. We use the macOS 26 Liquid Glass APIs unconditionally.
- **Universal binary** (x86_64 + arm64).
- **Current version:** v1.5.0 — see [RELEASES/](RELEASES/).

## Read these next, in order

1. **[ARCANII_DESIGN.md](ARCANII_DESIGN.md)** — module map, data flow, error mapping table. The "what's where" reference.
2. **[ARCANII_BACKLOG.md](ARCANII_BACKLOG.md)** — open follow-ups with effort tags. All P0/P1/P2/P3 items have shipped.
3. **[RELEASES/](RELEASES/)** — per-version release notes. v1.0.0 (initial fork) through v1.4.0 (widget).
4. **[WIDGET_SETUP.md](WIDGET_SETUP.md)** — kept around in case the widget target ever needs to be rebuilt; unused for everyday work.

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
│   └── Usage4Claude.entitlements  Main-app entitlements (sandbox off + App Group)
├── Tests/Usage4ClaudeCoreTests/   SwiftPM XCTest suite (currently SemverCompare only)
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

Currently 35 tests across `SemverCompareTests.swift`, `UsageResponseTests.swift`, and `ExtraUsageResponseTests.swift`. The test target is a SwiftPM package that lives alongside the `.xcodeproj`; it cherry-picks pure-function source files (`SemverCompare.swift`, `ClaudeAPIResponseModels.swift`) from `Usage4Claude/Helpers/`. To extend coverage, extract additional dependency-free helpers into `Usage4Claude/Helpers/` and add them to `Package.swift`'s `Usage4ClaudeCore` target's `sources` array. Anything that touches `L.*`, `UserSettings`, or `Logger` should stay in a sibling `+Formatting`-style file (see `UsageData+Formatting.swift`) so the test target doesn't have to drag in those dependencies.

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

Both main app (sandbox-off) and widget (sandbox-on) read/write to:
```
~/Library/Group Containers/group.com.arcanii.Usage4Claude/usage-snapshot.json
```
The main app writes on each successful `fetchUsage`; the widget reads on each timeline tick. `WidgetCenter.shared.reloadAllTimelines()` from the main app's success path nudges the widget for an immediate refresh.

## Quick context for the most-likely next tasks

- **Adding a new Settings field?** It's a `@Published` on `UserSettings`, persisted to `UserDefaults` in the `didSet`, restored in `init()`, and rendered in `Views/Settings/Tabs/GeneralSettingsView.swift` (or split if it belongs to its own concern — see the existing `+Accounts` / `+LaunchAtLogin` / `+SmartMode` extensions for the pattern).
- **Changing the popover UI?** `Views/UsageDetailView.swift`. The ring rendering with the glass-tube gradient + `.shadow` glow + `.glassEffect(in:)` is around the `if refreshState.isRefreshing` branches.
- **Tweaking smart-mode refresh timing?** `Models/UserSettings+SmartMode.swift` — the active → idleShort → idleMedium → idleLong tier transitions and tick counts.
- **Debugging an API failure?** `Services/ClaudeAPIService.swift`. The error mapping table is at the top of [ARCANII_DESIGN.md](ARCANII_DESIGN.md). 403 with `permission_error` body → `.sessionExpired` (auto-prompts re-login); 403 without that body or with HTML response → `.cloudflareBlocked`.

## Pinned versions

- Sparkle: `2.9.1` (pinned in `Usage4Claude.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`)
- Spoofed Chrome user-agent: `148.0.0.0` (in `ClaudeAPIHeaderBuilder.swift`)
- Tools required on the build machine: `xcodebuild` (Xcode 26.0+), `create-dmg` (`brew install create-dmg`), Sparkle's `sign_update` (download from sparkle-project releases; default location `/tmp/sparkle-tools/bin/sign_update`, override via `SIGN_UPDATE` env var)
