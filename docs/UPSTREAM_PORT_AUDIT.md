# Upstream Port Audit — pulling improvements from f-is-h/Usage4Claude

**Date:** 2026-07-09 (audit) · 2026-07-10 (ports 1–4 implemented) · **Method:** multi-agent comparison (map → per-area assess → adversarial verify → synthesize), 19 agents.
**Status:** ✅ audit complete; **ports 1–5 implemented on `main` (uncommitted), full app builds clean (Debug), 55/55 SwiftPM tests pass, all 5 `.strings` lint OK, and item 4 was smoke-tested live end-to-end on 2026-07-10** (signed sandboxed Debug build, real Anthropic sign-in).

## Implementation status (2026-07-10)

| # | Item | Status | Notes |
|---|------|--------|-------|
| 1 | ExtraUsage wire-model fix | ✅ done + 2 tests | `used_credits`→Double, added `monthly_limit`; 55/55 tests pass |
| 2 | 403 HTML-vs-JSON discrimination | ✅ done | `fetchOrganizations` now mirrors `fetchMainUsage` (HTML guard + `permission_error`→sessionExpired + 429) |
| 3 | Custom display → menu-bar-only | ✅ done | new `customDisplayMenuBarOnly` + `shouldShowCustomPlaceholderInPopover`; `forMenuBar:` on `getActiveDisplayTypes`; toggle + 5 locales (no fr) |
| 4 | System-browser OAuth sign-in | ✅ done + **verified live** | 6 new files, OAuth usage path, `network.server` entitlement, 9 strings × 5 locales; WebView login kept as cookie fallback |
| 5 | Multi-account `DEBUG_currentAccountId` + `accounts.first` fallback | ✅ done | Ported ahead of schedule: required to safely run a Debug build alongside the installed release app (they share a bundle id ⇒ UserDefaults domain) |

### Item 4 live smoke test (2026-07-10)

Signed Debug build with App Sandbox **on** and `com.apple.security.network.server` embedded (verified via `codesign -d --entitlements`). Confirmed from unified logs:

1. `nw_listener … local address: ::.1456 … reporting state ready` — **the sandboxed loopback listener binds**, which was the single riskiest unknown (without the entitlement it would go straight to `.failed`).
2. `ClaudeOAuth: opened system browser, waiting for authorization (callback port 1456)`
3. `Session expired — presenting WebLogin` → routed to the new OAuth window (the fork's v1.2.0 auto-relogin now lands on OAuth).
4. `Account refreshed` → `ClaudeOAuth: account created` — **the cookie→OAuth migration worked in place**, validating the adaptation to the fork's `addAccount` (same org UUID ⇒ credential overwritten, account id/alias preserved; no remove-then-add needed).
5. `Claude OAuth: refresh_token rotated, writing back silently` → `Claude session-token updated silently` — the trickiest path (single-flight refresh + rotation write-back via the new `silentlyUpdateCurrentClaudeSessionToken`) executed correctly.
6. `nw_listener … reporting state cancelled` — clean callback-server teardown.
7. Zero API errors after account creation; usage rendered in the menu bar.

## ✅ Hardening applied (2026-07-10) — was a follow-up from the smoke test

**The OAuth callback listener binds the wildcard address, not loopback.** Logs show `local address: ::.1456` with inbox flows started on `en0`, `awdl0`, `utun4`, etc. — so during the 5-minute sign-in window port 1456 is reachable from the LAN. This is **inherited verbatim from upstream** (`OAuthCallbackServer` deliberately omits `requiredLocalEndpoint` to serve both IPv4/IPv6 loopback; upstream's comment claims loopback-only, which is inaccurate).

Auth-code theft is not the risk (the code goes to the *user's* browser → localhost, and PKCE + a 32-byte `state` gate acceptance). The real issue is a **LAN denial-of-service**: `didDeliver` latches on the first request carrying `code` or `error`, and `handleCallback` fails closed on state mismatch — so any host on the network hitting `http://<lan-ip>:1456/callback?error=x` mid-sign-in kills that login attempt.

**Fixed:** `OAuthCallbackServer.handle(_:)` now drops any non-loopback peer before reading a byte, via a new `isLoopbackPeer(_:)` (handles the IPv4-mapped-IPv6 case `::ffff:127.0.0.1` and the full `127.0.0.0/8` block, not just `127.0.0.1`). The listener still binds wildcard (so both IPv4/IPv6 loopback resolve), but the peer check enforces loopback-only. Verified with a standalone harness compiling the real source: an 11-case decision-table test (which caught a `127/8` false-negative in the first draft), plus an e2e check that `127.0.0.1` and `[::1]` callbacks still deliver. Still worth sending upstream (their `CodexOAuth/OAuthCallbackServer.swift` is identical).

**Verification caveat noted for honesty:** an initial "LAN peer rejected ✓" curl result was a false positive — the macOS Application Firewall was blocking inbound LAN connections to the unsigned harness, so that probe never reached the guard. The decision-table test against the real `isLoopbackPeer` is the actual proof.

**Item 4 adaptations from upstream:** dropped `Account.provider` (Claude-only); used the fork's in-place `addAccount` instead of upstream's remove-then-add migration; renamed `codex_oauth_*` keys → `claude_oauth_*`; relocated `PKCE.swift`/`OAuthCallbackServer.swift` to a provider-neutral `Services/OAuth/`; inserted the OAuth branch into the fork's async `fetchUsage` (not upstream's DispatchGroup version); bundled item 1 (the OAuth `/api/oauth/usage` payload carries a float `used_credits`). Skipped all Codex files and `bec6cbd` per the Claude-only policy. New files were auto-included via the project's `fileSystemSynchronizedGroups` (no manual pbxproj edit).

---

_Original audit findings below (line numbers were leads to confirm; all confirmed during implementation)._

Companion to [UPSTREAM_CONTRIBUTIONS.md](UPSTREAM_CONTRIBUTIONS.md) (what we push **to** upstream); this doc tracks what we pull **from** upstream.

## Context

- **Fork baseline: upstream `v2.6.0`.** Initial commit `caed385` (2026-04-15) is byte-identical to upstream `v2.6.0` except 4 Xcode project files (signing/team, hardened runtime, dead-code stripping). Confirmed structurally: `ClaudeAPIResponseModels.swift:159` still carries the v2.6.0 `used_credits: Int?` shape (v2.6.1 changed it to `Double?`). No shared git history → **ports are manual re-application, not cherry-picks.**
- **Upstream today: `v3.2.2`**, ~87 commits / 11 releases past the fork point. The big post-baseline arc is the **v3.0.0 dual-provider (Codex) pivot**, which the fork deliberately does **not** follow (Claude-only policy, dated 2026-05-18 in `UPSTREAM_CONTRIBUTIONS.md`).
- **Arcanii-only divergences to respect on any port:** rename to `U4Claude`; macOS 26 / Liquid Glass rings; desktop widget + App Group; Sparkle (our v1.7.0, upstreamed as PR #56); App Sandbox + entitlements; English comments (upstream is Chinese); Chrome UA 149; localized Extra Usage currency; NDJSON history + sparklines; `UserSettings` split into `+Accounts/+LaunchAtLogin/+SmartMode`; async/await `fetchOrganizations`; auto re-login on session expiry; 5 locales (no French).

## Prioritized port list

| # | Item | Value | Effort | Upstream ref | Verified? |
|---|------|-------|--------|--------------|-----------|
| 1 | **ExtraUsageResponse wire-model fix** — `used_credits: Int?`→`Double?` + `monthly_limit` | 🔴 correctness | ~20 LOC + 2 tests | `42c7f56` (v2.6.1), wire half only | assess-only |
| 2 | **403 HTML-vs-JSON discrimination** in `fetchOrganizations` | 🟠 correctness | ~10 LOC | `d07e5dd` (v3.1.0), 403 half only | assess-only |
| 3 | **"Scope custom display to menu bar only"** toggle | 🟠 UX | ~70–90 LOC / 8 files | `e8e6d1c` (v3.2.0, issue #59) | assess-only |
| 4 | **System-browser OAuth sign-in** (Claude) | 🟢 strategic (high) | ~900 LOC, medium | `fadce35` + PKCE/callback from `db5ccb9` (v3.2.1) | assess-only |
| 5 | **Multi-account `DEBUG_currentAccountId` key + `accounts.first` fallback** | ⚪ dev-QoL | ~18 LOC | `bd019d7` (v3.0.0) | ✅ verified |

### 1. ExtraUsageResponse wire-model fix — *do this first*
The fork's v1.5.1 backport of `42c7f56` took the display half but **skipped the wire half**. The live API can return `used_credits` as a float (e.g. `21.0`); the fork's `Int?` decoder throws `typeMismatch`, the whole `ExtraUsageResponse` decode fails, and **Extra Usage silently disappears** for affected accounts. In `Usage4Claude/Helpers/ClaudeAPIResponseModels.swift` (~149–199): add `let monthly_limit: Int?` (new field; keep `monthly_credit_limit` + `spend_limit_amount_cents` as ordered fallbacks); change `used_credits` to `Double?` and adjust `toExtraUsageData()`. Port upstream's two tests (`testFractionalCentsInUsedCredits`, `testMonthlyCreditLimitFallback`). **Also a hard prerequisite for item 4** (the OAuth `/api/oauth/usage` payload embeds a float `used_credits`). Display side (`currencySymbol`, `%.2f`) is already done — don't re-touch.

### 2. 403 HTML-vs-JSON discrimination
Fork's async `fetchOrganizations` (`ClaudeAPIService.swift:274`) throws `cloudflareBlocked` on **all** 403s, so an expired/invalid sessionKey during WebLogin validation or manual-key entry is misreported as "Cloudflare blocked" instead of unauthorized. ~10 lines, reusing the fork's own Content-Type pattern from `fetchMainUsage` (162–190). `fetchMainUsage` itself needs no change — it already solved this better than upstream.

### 3. "Scope custom display to menu bar only"
Upstream issue #59 (`e8e6d1c`). Absent from the fork. Adds `@Published customDisplayMenuBarOnly` + a `forMenuBar:` param on `getActiveDisplayTypes` that forces `.smart` in the popover when the custom display is menu-bar-scoped. Smaller than upstream's diff (no Codex call sites to touch). ~70–90 lines across `UserSettings.swift`, `MenuBarIconRenderer.swift:44`, `UsageDetailView.swift:317`, `UsageDetailView+Helpers.swift:172`, `GeneralSettingsView.swift`, and `LocalizationHelper.swift` + 2 keys × 5 locales. Bonus: popover sparkline rows follow `activeDisplayTypes`, so they show the full smart set when the toggle's on.

### 4. System-browser OAuth sign-in — *the strategic one*
Port the **Claude half** of `fadce35` plus the two provider-neutral files it reuses (`PKCE.swift`, `OAuthCallbackServer.swift` — relocate out of `CodexOAuth/`). **Skip** all Codex pieces (policy) and `bec6cbd` (Codex silent-refresh; its only Claude-relevant bit is already in the fork). ~900 LOC: 6 new files (~700), the `ClaudeAPIService` OAuth usage path (~180), `hasValidCredentials` accepting the `sk-ant-ort01-` prefix + refresh-token rotation, `WebLoginWindowManager` routing to the compact OAuth window, and `com.apple.security.network.server` in the entitlements (one key; sandbox already on since v1.7.0, and upstream runs the same entitlement combo → sandbox risk pre-validated). Adaptations: drop `Account.provider`, simplify the migration to `addAccount`+`switchToAccount`, **bundle item 1**, anglicize comments, hand-register files in `project.pbxproj`.

**Why it's the strategic pick:** user-facing — passkeys + Microsoft/enterprise SSO finally work, and long-lived refresh tokens largely eliminate the sessionKey expiry that forced the fork's v1.2.0 auto-relogin. Maintenance — **OAuth accounts drop the Cloudflare bypass and the Chrome UA-spoof treadmill entirely** (bumped twice: v1.4.1, v1.7.1). Upstream code is stable (zero follow-up fixes v3.2.1→origin/main). Consider keeping WKWebView login as a fallback path. *(Directly answers Ben's 2026-07-09 "cloudflare bypass" question — see below.)*

### 5. Multi-account key fix *(only fully-verified item here)*
`bd019d7`: use `"DEBUG_currentAccountId"` as the UserDefaults key under `#if DEBUG`, and add `?? accounts.first` fallback in `currentAccount`. Fork stores accounts under a `DEBUG_`-prefixed key in Debug but `currentAccountId` shares one unprefixed key → alternating Debug/Release builds shows a spurious welcome window. ~18 lines in `UserSettings.swift` (touches the base file, not the `+Accounts` extension). Low value (dev-QoL + rare field robustness), but the cheapest possible port.

## ⚠️ Do NOT port (active hazards)

- **`CURRENT_PROJECT_VERSION = $(MARKETING_VERSION)`** (upstream `2e65ac1`/`36e06f2`/`8c6ed40`) — fixes an *upstream-only* Sparkle bug the fork never had. The fork uses a monotonic integer build (`17`, matching `<sparkle:version>17</sparkle:version>`). Porting it would make Sparkle rank installed build "17" above a new "1.7.2" and **permanently stop offering updates.**
- **Persistent `WKWebsiteDataStore.default()`** for web login (upstream `d07e5dd`) — upstream **reverted** it in `bec6cbd` because a persistent store auto-SSOs the previous account when adding a second. The fork is multi-account, so this would reintroduce the bug. Keep the current `.nonPersistent()` + clearing.
- **French localization** (`83da2a6`) — declined product decision; adopting it commits the fork to translating a 6th locale for every fork-only feature (widget, sparklines, Sparkle UI) forever. Fully verified as a clean-but-unwanted port. No action.
- **Codex / dual-provider** (`ad3f72c` + ~20 follow-ups) — settled Claude-only policy; ~multi-week port into heavily-diverged files. Revisit only if the maintainer starts using Codex CLI.

## Already-have (no action)

- **Sparkle in-app updates** — the fork *originated* this (v1.3.0; upstreamed as PR #56). Fork copy is ahead: notarized+stapled DMGs, sandbox XPC entitlements.
- **Usage notifications** — full feature in the v2.6.0 base (90% warn, reset detection, 75% early warning), plus a fork-only sandbox guard. *Adjacent gap (belongs to Codex area): per-account dedup keying — see bonus below.*
- **App Nap / wake-idle / HTTP-3 reliability** — `7a1f045` (in base), `de671c6` and `9feb1fc` already backported (v1.5.1).
- **i18n fixes** — Japanese kanji (`753b6bc`) and currency symbol (`4dc411b`) already backported; Korean website present.

## Bonus — latent issues surfaced (not upstream ports)

- **Dead code / spurious reset notification:** fork keys notification dedup by `LimitType.rawValue` only; `resetAllNotificationStates()` has zero call sites; account switch (`MenuBarManager.swift:180`) refetches without clearing `usageData`. Switching from a ≥90% account to a lower one can fire a spurious reset notification. ~30-line fix (per-account keying on `currentAccountId`, clear on `.accountChanged`/`removeAccount`).
- **Stale CI release path:** the fork's `.github/workflows/release.yml` is untouched since the initial commit and dead by design (releases are local via `scripts/build.sh`). If a `[release]` commit ever touched the stale `CHANGELOG.md` it could emit an unsigned, wrongly-named draft. Consider deleting it alongside stale `docs/DAILY_RELEASE_WORKFLOW.md`.

## Tie-in: Ben's "cloudflare bypass" question (2026-07-09)

The Cloudflare header-emulation in `ClaudeAPIHeaderBuilder.swift` is inherited from upstream (v2.6.0 base), not Arcanii-original — the fork only anglicized comments and keeps the Chrome UA current (131 → 149). **Item 4 (OAuth sign-in) is the real answer to "still the direction you're taking?":** upstream has since moved auth to a system-browser OAuth flow that, for OAuth accounts, retires both the header-emulation bypass and the UA-bump treadmill. If asked, the honest framing is "the bypass is upstream's approach for cookie-session accounts; upstream's newer OAuth path (which I can port) supersedes it."

## Provenance

Reference clone `../Usage4Claude` (read-only, `origin/main` @ v3.2.2). Full agent transcripts: session `subagents/workflows/wf_4611ab88-cd5/journal.jsonl`. Re-run/resume: `Workflow({scriptPath: ".../upstream-improvements-audit-wf_4611ab88-cd5.js", resumeFromRunId: "wf_4611ab88-cd5"})` — completed agents replay from cache; only the failed verify/synthesize agents re-run (once spend limit resets).
