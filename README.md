# U4Claude (Arcanii Mod)

A personal fork of [**f-is-h/Usage4Claude**](https://github.com/f-is-h/Usage4Claude) — the original menu-bar Claude usage monitor. **All credit for the underlying app goes to [@f-is-h](https://github.com/f-is-h)** — this fork only layers a few macOS 26 / Tahoe niceties on top.

> Forked from upstream **v2.6.0** (April 2026). Thank you f-is-h! 🙇

<div align="center">

<img src="docs/images/icon@2x.png" width="256" alt="U4Claude icon">

[![macOS](https://img.shields.io/badge/macOS-26.0%2B-blue?style=flat-square)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-6.2-orange?style=flat-square)](https://swift.org)
[![SwiftUI](https://img.shields.io/badge/SwiftUI-✓-green?style=flat-square)](https://developer.apple.com/xcode/swiftui/)
[![Sparkle](https://img.shields.io/badge/Sparkle-2.9.1-purple?style=flat-square)](https://sparkle-project.org)
[![License](https://img.shields.io/badge/License-MIT-purple?style=flat-square)](LICENSE)
[![Release](https://img.shields.io/github/v/release/arcanii/Usage4Claude-Arcanii?style=flat-square)](https://github.com/arcanii/Usage4Claude-Arcanii/releases)

**A macOS menu-bar app for real-time monitoring of your Claude AI usage — with Liquid Glass rings, a desktop widget, and one-click in-app updates.**

<img src="docs/images/ClaudeUsage.png" width="256" alt="Claude Usage">
<img src="docs/images/Widget.png" width="256" alt="Widget">






[What's different](#-whats-different-in-this-fork) • [Install](#-install) • [Features](#-features) • [User guide](#-user-guide) • [FAQ](#-faq)

</div>

---

## 🌀 What's different in this fork

This fork tracks the upstream feature set faithfully (all the features listed below come from f-is-h). It adds a small set of macOS 26 / Tahoe-specific changes:

| Change | Since |
|---|---|
| **Weekly per-model limits, named by the API** — Claude moved weekly per-model limits into a `limits[]` array keyed by model display name, so the old fixed Opus/Sonnet fields can come back empty. Rows are read from the array and labeled with the real model (e.g. "Fable"), a third or later model gets its own row, and the two legacy slots stay position-fixed — upstream's equivalent refactor collapses them and mislabels a Sonnet-only week | v1.9.0 |
| **System-browser OAuth sign-in** — "Sign in with Claude" runs the Claude OAuth (PKCE) flow in your default browser instead of an embedded `WKWebView`, so Google / Microsoft / enterprise SSO / passkey logins all work ([upstream #49](https://github.com/f-is-h/Usage4Claude/issues/49)). A short-lived local listener catches the `localhost` redirect — it accepts loopback peers only, and adds the `com.apple.security.network.server` entitlement. OAuth accounts read usage with a Bearer token and skip the Cloudflare header path entirely; legacy session-key accounts are unchanged | v1.8.0 |
| **Custom display → menu-bar-only toggle** — scope your custom limit selection to just the menu-bar icon; the popover then falls back to smart display and shows every limit that has data | v1.8.0 |
| **App Sandbox enabled** — `com.apple.security.app-sandbox = YES` with explicit `network.client`, App Group, and Sparkle XPC mach-lookup entitlements. Defense-in-depth + a verifiable "no telemetry" claim. Existing users need a one-click re-login after update (Keychain access-group change) | v1.7.0 |
| **24h sparkline strip** under every limit row in the popover + **expanded the widget gallery to 5 kinds** (original rings, ring + 24h sparkline, dual 5h/7d sparkline, large dashboard, extra-large full dashboard). History storage moved to NDJSON in the App Group container — O(1) append per fetch | v1.6.0 |
| **API response models extracted** with SwiftPM unit coverage (65 tests today); `fetchOrganizations` migrated to `async/await` | v1.5.0 |
| **Spoofed Chrome user-agent** kept current (149 as of 2026-06) | v1.4.1 |
| **Auto-relogin throttle** that recovers from a dismissed WebLogin window | v1.4.1 |
| **Glass-tube popover rings** with a configurable illumination slider in General Settings → "Popover Appearance" | v1.3.1 / v1.4.1 |
| **Desktop widget** (small + medium) reading from an App Group snapshot — no extra API calls | v1.4.0 |
| **macOS 26 / Tahoe minimum** (was 13.0) — uses Apple's Liquid Glass material unconditionally | v1.4.0 |
| **One-click in-app updates** via [Sparkle](https://sparkle-project.org) (EdDSA-signed) — replaces the old "download → drag-to-Applications" flow | v1.3.0 |
| **Bundled as `U4Claude.app`** with bundle id `com.arcanii.Usage4Claude` so it can coexist with the upstream `Usage4Claude.app` | v1.0.0 |

The fork is maintained by [@arcanii](https://github.com/arcanii) as a personal mod. Issues and PRs welcome here, but for **general** Usage4Claude contributions, please go upstream to [f-is-h/Usage4Claude](https://github.com/f-is-h/Usage4Claude) — that's the canonical project.

---

## ✨ Features

(Inherited from upstream unless marked "fork".)

### Core monitoring
- **Real-time** Claude subscription (Free/Pro/Team/Max) usage in the menu bar
- **All your limits** simultaneously: 5-hour, 7-day, Extra Usage, and the weekly per-model limits the API reports (Opus / Sonnet / Fable — named dynamically)
- **Smart display** auto-detects available limit types; **custom display** lets you pick any combination
- **Smart colors** — green → orange → red on the 5-hour ring; cyan → purple on 7-day; per-color schemes for Opus / Sonnet / Extra
- **Cross-platform** — same quota whether you're using claude.ai web, Claude Code, the desktop app, mobile, or Cowork

### UI & display
- **Multiple display modes**: Percentage Only, Icon Only, Icon + Percentage, Unified concentric rings
- **Three icon styles**: Color Translucent, Color with Background, Monochrome (template — adapts to system menu bar)
- **Glass-tube popover rings** with user-tunable illumination *(fork)*
- **Desktop widgets** — 5 kinds (rings, trend sparklines, and large / extra-large dashboards; small → extra-large) *(fork)*
- **Time format**: System / 12-hour / 24-hour
- **Appearance**: System / Light / Dark
- **Localization**: English, 日本語, 简体中文, 繁體中文, 한국어

### Refresh & notifications
- **Smart refresh** — adaptive 4-tier (active 1m → idle-short 3m → idle-medium 5m → idle-long 10m), or fixed (1 / 3 / 5 / 10 min)
- **Manual refresh** with 10-second debounce (`⌘R`)
- **Usage notifications** at 90% and on reset (toggleable)
- **In-app updates via Sparkle** *(fork)* — background daily check + manual "Check for Updates" with EdDSA verification

### Auth
- **Multi-account / multi-org** — `⌘1`–`⌘9` to switch
- **Sign in with Claude** *(fork)* — runs the Claude OAuth (PKCE) flow in your default browser and returns via a `localhost` callback; supports Google / Microsoft / enterprise SSO / passkey logins that an embedded WebView can't do
- **Built-in WebLogin** — opens claude.ai in an embedded `WKWebView` and scrapes `sessionKey` automatically (no DevTools fishing); still available for session-key accounts
- **Auto-relogin prompt** when the session expires — including recovery from a dismissed login window *(fork)*
- **Keychain-stored credentials** — OAuth refresh tokens and legacy session keys alike; no plaintext on disk

### Convenience
- Launch at Login (`SMAppService`)
- Keyboard shortcuts: `⌘R` refresh, `⌘,` General Settings, `⌘⇧A` Auth Settings, `⌘Q` quit
- Welcome wizard on first launch
- Diagnostic export (redacted) for support
- Universal binary (Intel + Apple Silicon)

### Privacy
- All data stored locally; no telemetry, no analytics, no third-party services
- Network calls go to `claude.ai` (session-key accounts), Anthropic's OAuth hosts `console.anthropic.com` / `api.anthropic.com` (OAuth accounts), and (for updates) `raw.githubusercontent.com` (Sparkle appcast). Signing in also runs a short-lived listener on `localhost` to catch the browser redirect; it accepts loopback connections only
- Source 100% open under MIT

---

## 💾 Install

### Download (recommended)

1. Grab the latest `.dmg` from [**Releases**](https://github.com/arcanii/Usage4Claude-Arcanii/releases).
2. Mount it, drag `U4Claude.app` to `/Applications`.
3. First launch: right-click → **Open** to bypass Gatekeeper's quarantine prompt for an externally-distributed app.
4. Allow Keychain access for the session key on first save.

After v1.3.0+, future updates install via the in-app **Check for Updates** menu (or the automatic 24h background check) with no further drag-and-drop.

### Build from source

```bash
git clone https://github.com/arcanii/Usage4Claude-Arcanii.git
cd Usage4Claude-Arcanii

# Debug build (Xcode 26.0+ required)
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project Usage4Claude.xcodeproj -scheme Usage4Claude \
  -configuration Debug -allowProvisioningUpdates build

# Run tests (65 tests, SwiftPM target)
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

For the full release pipeline (signed → notarized → stapled → Sparkle-signed DMG), see [`scripts/build.sh`](scripts/build.sh) and the [release runbook in HANDOVER.md](docs/HANDOVER.md#releasing).

**Requirements**: macOS 26.0 (Tahoe) or later, Xcode 26.0+, an Apple Developer account if you want to sign + notarize. Universal binary (x86_64 + arm64).

---

## 📖 User guide

### Initial setup

1. **Launch** — the welcome screen appears on first run.
2. **Authenticate** — three paths:
   - **Sign in with Claude** (recommended): click the button; your default browser opens the Claude OAuth flow and the app picks the result up automatically via a `localhost` callback. Works with Google / Microsoft / enterprise SSO / passkey logins.
   - **Browser Login**: logs into claude.ai in the embedded browser and extracts the session key automatically.
   - **Manual paste**: open claude.ai → DevTools → Network → find a `usage` request → copy `sessionKey=sk-ant-…` from the Cookie header.

### Daily use

- Click the menu bar icon → popover with detail rows.
- Tap a row to toggle between *reset time* and *remaining quota* — the ring fill also inverts so the visible arc represents the slice you have left rather than the slice you've used *(fork, v1.6.4)*.
- Long-press the ring (3 s) to cycle the loading-animation style.
- `⌘R` to refresh; `⌘,` for General Settings; `⌘⇧A` for Auth Settings; `⌘Q` to quit.
- Right-click the menu bar icon for the same menu the popover's `…` button shows.
- Multi-account: `⌘1`–`⌘9` to switch between configured accounts.

### Refresh modes

- **Smart** (default) — 1 min while you're active, drops to 3 / 5 / 10 min after consecutive unchanged ticks. Snaps back to 1 min on any utilization change, manual refresh, or popover open.
- **Fixed** — pick 1 / 3 / 5 / 10 min and stay there.

### Updating

- **Background**: Sparkle polls the appcast once every 24 h. When a newer signed build is available, you get a Sparkle prompt — Install / Skip / Remind Later.
- **Manual**: `…` menu → **Check for Updates**.
- **Verification**: every update is EdDSA-signed; Sparkle refuses tampered or corrupted DMGs.

---

## ❓ FAQ

<details>
<summary><b>What if the app shows "Session Expired"?</b></summary>

Session keys expire periodically (weeks to months). The app auto-prompts a re-login window on the first expiry; if you dismiss it, hitting the refresh button (or reopening the popover after 30 s) re-prompts. You can also re-login manually from Settings → Authentication.

</details>

<details>
<summary><b>How much does it cost in resources?</b></summary>

Lightweight: well under 0.1 % CPU at idle, ~20 MB resident memory, one HTTPS request per refresh tick. The widget extension reads from a shared file — it doesn't make its own network calls.

</details>

<details>
<summary><b>Why does this fork need macOS 26 / Tahoe?</b></summary>

The popover rings layer Apple's [Liquid Glass](https://developer.apple.com/design/human-interface-guidelines/) material via `.glassEffect(in:)`, which is macOS 26 only. If you're on macOS 13–15 and don't need that look, the upstream [f-is-h/Usage4Claude](https://github.com/f-is-h/Usage4Claude) keeps a 13.0+ deployment target and is the right choice for you.

</details>

<details>
<summary><b>Does it work with Claude Code / Desktop / Mobile / Cowork?</b></summary>

Yes — all Claude products share the same usage quota, so a single `sessionKey` covers them all. You'll see your combined usage in the menu bar regardless of which clients you're hitting the API from.

</details>

<details>
<summary><b>Is my data safe?</b></summary>

Yes. Session keys and OAuth refresh tokens live in macOS Keychain (AES-256, hardware-protected on T2/Apple Silicon). The Organization ID lives in `UserDefaults` (it's not a credential, it's a UUID). Nothing leaves your Mac except the calls to `claude.ai/api/...`, Anthropic's OAuth hosts (`console.anthropic.com`, `api.anthropic.com`) for OAuth accounts, and (for updates) the raw GitHub host serving the Sparkle appcast. **Both the main app and the widget extension run under App Sandbox** *(fork, v1.7.0)*; you can verify with `codesign -d --entitlements - /Applications/U4Claude.app` that the outbound network capabilities are `network.client` plus `network.server` — the latter used only for the short-lived `localhost` listener that catches the OAuth redirect during sign-in, which accepts loopback connections only — and the only file access outside the container is the App Group + Sparkle's XPC services.

</details>

<details>
<summary><b>Can't see the menu bar icon?</b></summary>

Some macOS versions and third-party tools (Bartender, Hidden Bar) auto-hide infrequently used items. Hold **⌘** and drag icons to rearrange them; drop the U4Claude icon somewhere visible. On Sonoma+ also check System Settings → Control Center.

</details>

<details>
<summary><b>How do I add the desktop widget?</b></summary>

Run U4Claude at least once (so it writes the App Group snapshot), then right-click on your desktop → **Edit Widgets…** → search "Claude Usage" → drag your preferred kind — rings, sparkline, dual sparkline, or large / extra-large dashboard — onto the desktop. The widget refreshes immediately on every successful main-app fetch.

</details>

---

## 🛠 Tech stack

- **Swift** 6.2, MainActor default isolation
- **SwiftUI** + AppKit hybrid (popover, menu bar item, settings windows)
- **Combine** for view-model bindings
- **App Group** (`group.com.arcanii.Usage4Claude`) shared by main app + widget
- **Sparkle** 2.9.1 (EdDSA-signed in-app updates)
- **WidgetKit** for the desktop widget
- **OAuth 2.0 + PKCE** system-browser sign-in; the `localhost` authorization-code redirect is caught by an `NWListener` (`Network` framework) that accepts loopback peers only — requires `com.apple.security.network.server` *(fork)*
- **macOS 26.0+**, Universal binary (x86_64 + arm64)

For the architecture map, error mapping table, and release runbook, see [`docs/HANDOVER.md`](docs/HANDOVER.md) and [`docs/ARCANII_DESIGN.md`](docs/ARCANII_DESIGN.md).

---

## 🗺 Roadmap

### Closed in this fork
- [x] **v1.0.0** — initial fork with dual display + branding
- [x] **v1.1.0** — notarized DMG, session-expired error mapping fix
- [x] **v1.2.0** — auto-prompt re-login, ⌘1–⌘9 account switching, CSV history export, multi-account refinements
- [x] **v1.3.0** / **v1.3.2** — Sparkle in-app updates (EdDSA-signed)
- [x] **v1.3.1** — glass-tube glow on popover rings + macOS 26 Liquid Glass
- [x] **v1.4.0** — desktop widget extension + App Group snapshot
- [x] **v1.4.1** — ring illumination slider, auto-relogin throttle fix, Chrome UA bump
- [x] **v1.5.0** — API response models extracted, 24 new transform tests, `fetchOrganizations` async/await migration
- [x] **v1.5.1** — backported upstream v2.6.1 fixes: HTTP/3 disabled on API requests (proxy-friendliness), Extra Usage shown with cents precision
- [x] **v1.6.0** — usage history visible: 24h sparkline under every popover row, plus four new desktop widget kinds (Large Dashboard, Sparkline, Dual-Sparkline, ExtraLarge). Storage rebuilt on NDJSON in the App Group container.
- [x] **v1.6.1** — three upstream backports: refresh on system wake, idle→active timer restart, 7-day placeholder for new accounts.
- [x] **v1.6.2** — "Reset Widgets" recovery action in the popover `…` menu (medium reset; ⌥-click for hard reset via chronod restart).
- [x] **v1.6.3** — two upstream backports: Japanese kanji fix for the 24h hour suffix, session-key hint wording generalized.
- [x] **v1.6.4** — three upstream backports: Google OAuth login fix (`WKUIDelegate` for `window.open()` popups + base-domain `allowedDomains`), "View Claude Usage" menu item replaced with "Claude Status" (status.claude.com), and detail rings now visually invert in remaining mode (fill drains from the top, center label flips Used ↔ Available).
- [x] **v1.7.0** — **App Sandbox enabled.** Main app now runs under `com.apple.security.app-sandbox = YES` with Sparkle's XPC services wired via `temporary-exception.mach-lookup.global-name`. Retires the v1.6.2 "Reset Widgets" feature (the hard-reset tier needed subprocess execution, blocked by sandbox; the medium tier wasn't worth the menu real estate alone). Existing users need a one-click re-login after update.
- [x] **v1.9.0** — **Weekly per-model limits, read and named correctly.** Claude's API moved weekly per-model limits out of the dedicated Opus/Sonnet fields into a `limits[]` array keyed by model display name, so v1.8.0 showed **no weekly model row at all** on affected accounts. The row is back, labeled with the actual model (e.g. "Fable"), and a third or later model gets its own popover row. Also: notifications no longer vanish when the app is foregrounded, browser sign-in gains a paste-the-link fallback plus 401 self-heal, `accept-language` follows your system locale instead of a hardcoded `zh-CN`, refresh timers scheduled off-main no longer silently fail to start, and PKCE now checks its RNG status. No re-login.
- [x] **v1.8.0** — **System-browser OAuth sign-in.** "Sign in with Claude" runs the Claude OAuth (PKCE) flow in your default browser, replacing the embedded `WKWebView` as the default and unblocking Google / Microsoft / enterprise SSO / passkey logins (closes upstream [#49](https://github.com/f-is-h/Usage4Claude/issues/49)). The `localhost` redirect is caught by a short-lived listener that accepts loopback peers only (adds `com.apple.security.network.server`), and OAuth accounts fetch usage with a Bearer token, skipping the Cloudflare header path — legacy session-key accounts are unchanged and keep the embedded WebLogin. Also adds an "apply custom display to menu bar only" toggle, plus three fixes: fractional Extra Usage credits no longer make the row vanish, an expired session key now reports "session expired" instead of "Cloudflare blocked", and both the HTTP-error text and the auth-error "Go to Settings" button are now correct in all five languages.
- [x] **v1.7.1** — Extra Usage currency-symbol localization (renders your account's billing currency, + KRW for the Korean locale) and the spoofed Chrome UA bumped to 149. Small maintenance release; no migration, no re-login.

See [`docs/RELEASES/`](docs/RELEASES/) for full per-version notes.

### Open
- [ ] Richer history surface (e.g. a "History" tab). *(A sparkline overlay on the popover ring was explored and shelved — redundant with the per-row strips; see `docs/ARCANII_BACKLOG.md`.)*
- [ ] Recurring Chrome UA bump (cron / scheduled agent) — now only affects legacy session-key accounts; OAuth accounts don't send a spoofed UA
- [ ] Widget bundle ID rename (deferred — breaks the existing App Group profile)
- [ ] iOS-continuity accessory widgets for Control Center (optional)

See [`docs/ARCANII_BACKLOG.md`](docs/ARCANII_BACKLOG.md) for effort tags.

---

## 🤝 Contributing

This is a personal fork. Issues and PRs are welcome — file them at [arcanii/Usage4Claude-Arcanii](https://github.com/arcanii/Usage4Claude-Arcanii/issues).

For **general** Usage4Claude contributions (features that should land for everyone, not just Tahoe users), please contribute upstream to [**f-is-h/Usage4Claude**](https://github.com/f-is-h/Usage4Claude) — that's where the broader community lives.

See [`CONTRIBUTING.md`](CONTRIBUTING.md) for the upstream contribution guide (still applies here).

---

## 📝 Changelog

See [`CHANGELOG.md`](CHANGELOG.md) for upstream history. Fork-specific notes live in [`docs/RELEASES/`](docs/RELEASES/) — one file per fork release.

---

## 📄 License

MIT — see [`LICENSE`](LICENSE). Original copyright © 2025 [f-is-h](https://github.com/f-is-h); fork modifications © 2026 [arcanii](https://github.com/arcanii). Both retained under the same MIT terms.

---

## 🙏 Acknowledgments

- **[@f-is-h](https://github.com/f-is-h)** for building the original Usage4Claude — none of this exists without his work.
- **[Anthropic](https://anthropic.com)** for Claude.
- **[Sparkle](https://sparkle-project.org)** for the in-app update framework.
- The original icon was inspired by Claude AI's branding.

---

## ⚖️ Disclaimer

This is an independent third-party tool with no official affiliation with Anthropic or Claude AI. The app authenticates via the same private `claude.ai/api/organizations/<id>/usage` endpoint the website uses; if Anthropic changes that endpoint, the app will break until updated. Please comply with [Claude AI's Terms of Service](https://www.anthropic.com/legal/consumer-terms) when using this software.

---

<div align="center">

If this fork helps you, **star it** — and please also star [**upstream**](https://github.com/f-is-h/Usage4Claude) where the real work happens.

Forked with care by [@arcanii](https://github.com/arcanii) · [⬆ Back to top](#u4claude-arcanii-mod)

</div>
