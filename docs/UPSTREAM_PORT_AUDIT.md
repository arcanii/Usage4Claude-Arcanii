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

---

# Delta audit #3 — upstream post-v3.3.0 (2026-09-02)

> **STATUS: all four ports applied 2026-09-02** (commits `b2c9606`, `3460dd2`+`e83df2d`, `3233dd7`, `3cff48a`; shipping as v1.9.3).
> Every claim below was re-verified against the real tree before editing, with an adversarial refutation pass per area. Corrections found:
> - **Two** compile breaks for the Optional `five_hour`, not one — `ClaudeAPIResponseModels.swift:100` (`parseLimitData` takes a non-optional, dragging `:154`) as well as `DiagnosticManager.swift:326`.
> - **Missing edit:** once `five_hour` is Optional an all-null payload *decodes cleanly*, so `DiagnosticManager.analyzeResponse` falls into `createReportForSuccess` and reports a healthy connection reading "utilization: n/a". The all-null branch there is part of the fix, not polish.
> - **Missing edit:** `92223a2` touches 10 files; the write-up listed 4 sites across 2. `AboutView.swift` `Spacer()` → `Spacer(minLength: 0)` was omitted. (Its `alignment: .top` is nonetheless the load-bearing change, and it covers all three tabs — the write-up's "symptom-masking" framing was wrong.)
> - **Banner design:** the view-layer string gate proposed here is unsafe. `errorMessage` is a snapshot while `L.Error.*` re-resolves per access, so a language switch with a live auth error reclassifies it as transient. Landed with the typed `errorRequiresFullScreen` instead. Three further defects had to be handled — a latch (the banner would otherwise blink and resize the popover on every manual refresh), account-switch suppression (`usageData` still holds the previous account's numbers), and an `!activeDisplayTypes.isEmpty` guard. `.usageDashboardUnavailable` — added by this very audit's port 2 — would have landed in the transient bucket and been hidden behind a "refresh failed" banner.
> - **Overstated:** the OAuth port. The ordinary paths already call `stop()` via `onDisappear`; the real gap is only the dealloc path. `start()` also tries multiple ports and sets `allowLocalEndpointReuse = true`, so a single leaked listener need not surface at all. The load-bearing detail is that it must be `listener?.cancel()`, not `deinit { stop() }`, under `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.


**Upstream:** `1b42d1e` (2026-09-01), still tagged **v3.3.0** — 11 commits since the previous baseline `25bdf2b`.
**Fork:** v1.9.2 shipped. Method: same fan-out (assess per area → adversarial verify → synthesize).
**Status:** 6 areas assessed; verifications returned `holds=true` on every port/partial recommendation checked. The workflow run was `wf_cd18d6ec-42d` (journal under this session's `subagents/workflows/`); the final synthesis agent had not reported when this was written, but the per-area results below are complete and verified.

## 🔴 Port — both are TOTAL-fetch failures, not missing rows

### 1. `five_hour` must be Optional (upstream `3878868`, PR #80) — high / small
**CONFIRMED EXPOSED, unmodified.** `Usage4Claude/Helpers/ClaudeAPIResponseModels.swift:47` declares `let five_hour: LimitUsage` — the **only** non-optional window (`seven_day`:49, `seven_day_oauth_apps`:51, `seven_day_opus`:53, `seven_day_sonnet`:55, `limits`:62 are all optional). A `"five_hour": null` payload makes JSONDecoder throw `valueNotFound` and kills the **entire** decode. Upstream cites real accounts (Team plans) returning it null.

Both fetch paths die: session-key at `ClaudeAPIService.swift:277-283` → `UsageError.decodingError`; OAuth at `:629` (error at `:671`).

Fix is ~3 lines + one diagnostics fix. Everything downstream **already tolerates nil** — `UsageData.fiveHour` is already `LimitData?` (:289), and there are **zero force-unwraps of `fiveHour` in the tree** (verified across MenuBarUI, MenuBarIconRenderer, UsageDetailView(+Helpers), UsageRowComponents, NotificationManager, UsageSnapshotBridge, UsageHistorySampleBridge/Store). Adapt upstream's `toUsageData()` to the fork's own init (`fiveHour:sevenDay:legacyOpus:legacySonnet:scopedWeeklyModels:extraUsage:`) — **not** upstream's `weeklyModels:`.

### 2. Plans without a usage dashboard (upstream `494957d`) — high / small
Same root cause, different symptom. Trigger: HTTP 200 with **every** window null — Free Tier, and Team/Enterprise orgs that haven't enabled the member usage dashboard. The fork emits `decodingError`, which maps to *"Failed to parse response data. Please check if your credentials are correct."* (`en.lproj:179`) — **wrong advice for valid credentials**; it sends people to re-authenticate for nothing. `DiagnosticManager.swift:273` repeats the wrong verdict. Needs a distinct error case + string in the fork's 5 locales.

## 🟠 Partial

### 3. Stale-data banner on transient errors (upstream `a23c801`, PR #75) — high / small
The fork already keeps `usageData` on failure (piece 2 is a non-issue — Claude-only, no `fetchClaudeOnly`/`clearClaudeUsageState`). **Missing piece is the view layer**, which is the part that fixes what was actually observed: `UsageDetailView` should show cached numbers with a stale-data banner instead of a full-screen error, gated on `errorMessage != nil && usageData != nil && !errorRequiresAuthAction`. Needs `@Published errorRequiresAuthAction` on `DataRefreshManager` (typed switch over `.unauthorized/.sessionExpired/.noCredentials`), a `staleDataBanner`, +53pt popover height, and `error.showing_cached_data` in the fork's **5** locales (upstream has 7). Note the fork already replaced upstream's string-matching auth check with `isAuthenticationError(_:)`, so wire the banner to that rather than reintroducing string matches.

### 4. `OAuthCallbackServer` deinit (upstream `417a0d3` / PR #77) — medium / small
**GAP IS REAL AND UNFIXED.** Only one hunk of that PR is provider-neutral: a `deinit { listener?.cancel() }` after `private var didDeliver = false`. Without it a login window closed mid-flow can leave an `NWListener` bound to 1456/1458 for the app's lifetime → spurious "port busy" on retry. **SKIP** the rest of PR #77: the `shared` singleton keep-alive, the Codex manual-paste (the fork already has a better Claude version at `ClaudeOAuthCoordinator.swift:94-161`), the `codex_cli_simplified_flow` param, Codex locale aliases, and the window-height change (fork is already 440×380).

### 5. Settings-tab stability (upstream `92223a2`) — medium / small, cosmetic
Fork's `SettingsView.swift` is byte-identical to upstream's pre-fix version apart from translated comments, so all three defects are present. Load-bearing fix: `SettingsView.swift:81` `.frame(width: 500, height: 550)` → add `alignment: .top` (AboutView is a rigid VStack; centre alignment pushes the tab strip above the window edge, clipped and partly unclickable). Plus `ToolbarButton.swift:21-30` icon `.frame(24×24)`, label `.lineLimit(1)`/`.minimumScaleFactor(0.85)`, and `.padding(.vertical, 8)` → `.frame(height: 54)`.

## ✅ Already-have / skip
- **Redundant incoming-connections build setting** (`1b42d1e`) — the fork already sits at the post-revert value in both app-target configs. Nothing to do.
- **Codex reset announcement badge** (`188554f`), **sponsorship links** (`bda4ce5`) — Codex-only / not applicable.

## Does NOT change the upstream-PR plan
PR #77's callback change is a `deinit`, **not** the wildcard-bind hardening. The fork's loopback-peer fix and the `59f4efd` weekly-slot-collapse bug both remain unreported upstream — see `UPSTREAM_CONTRIBUTIONS.md`.

## Synthesis refinements (arrived after the above was written)

Three corrections to the port list — the synthesis agent reported last:

1. **Do ports 1 and 2 as ONE commit, with `494957d` as the superset.** They overlap almost entirely and touch the same lines (`ClaudeAPIResponseModels.swift:47/100/154`, `DiagnosticManager.swift:326`). `494957d` already contains the optional-`five_hour` change and adds the "dashboard unavailable" diagnosis on top — porting them separately means editing the same lines twice.

2. **There is exactly one compile-breaking site.** `DiagnosticManager.swift:326` reads `usageData.five_hour.utilization` and will not compile once the field is optional. It must be fixed in the same commit. Note `createReportForSuccess` (`:302`) is an implicit-return single-expression body, so introducing a `let` also requires adding an explicit `return`:
   ```swift
   let fiveHourSummary = usageData.five_hour.map { "\($0.utilization)%" } ?? "n/a"
   return DiagnosticReport(
       responseBodyPreview: "Valid usage data received (utilization: \(fiveHourSummary))",
   ```
   Putting `%` inside the `.map` avoids upstream's slightly wrong `"n/a%"`. These preview strings are hardcoded English, so **no localization work** for this part. `docs/archive/DIAGNOSTICS_IMPLEMENTATION.md:627` quotes the old line — archived, leave it.

3. **The damage is worse than a blank UI: it silently loses history.** `UsageHistoryStore.shared.append(data)` sits in the success branch (`DataRefreshManager.swift:170`); the failure branch (`:202`) only sets `errorMessage`. So for an affected account every tick writes **nothing** to the append-only NDJSON — a permanent, unrecoverable gap — and leaves a stale widget snapshot. And `DiagnosticManager.swift:273`'s `try?` fails, so the built-in diagnostic reports "Data Parsing Error / check if your credentials are correct" at medium confidence, actively pointing the user at a problem that does not exist.

Worst case isn't the all-null payload: it's an account returning `five_hour: null` alongside **real** `seven_day` / `limits[]` data — a fully usable response thrown away.

Suggested tests (SwiftPM target already compiles `ClaudeAPIResponseModels.swift`): upstream's all-null decode test; a field-absent-entirely variant; a **fork-only** regression pairing `"five_hour": null` with a populated `limits[]` asserting `opus`/`sonnetModelName` still resolve (proves a null five_hour doesn't disturb `scopedWeeklyModels` slot resolution); and `primaryLimit` falling back to `sevenDay`.

---

# Delta audit #4 — upstream v3.3.0 → v3.5.0 (2026-10-25)

**Upstream:** `e0030f1`, tagged **v3.5.0** — **71 commits** since audit #3's baseline `1b42d1e`. Three upstream releases in between (v3.4.0, v3.4.1, v3.5.0).
**Fork:** v1.9.3 shipped (`c45cc84`). Method: scope inline → 5 themed areas assessed in parallel → an adversarial refutation pass per area (10 agents). **Every refutation returned `refuted=true`**, and between them they overturned two whole commits the areas had omitted, flipped three verdicts, and caught one proposed edit that was a silent no-op. Corrections are folded in below rather than left in the area reports.

**Toolchain moved too.** The machine now runs **macOS 27.0.1**, with **Xcode 27.1** and the macOS 27.0 SDK as the only installed SDK. The fork still builds clean on it (`MACOSX_DEPLOYMENT_TARGET = 26.0`) and all 72 tests pass — verified 2026-10-25. This changes which half of upstream's macOS 27 work applies; see A1.

**Two scoping errors to record, both mine.** `908f3ce` was filed as Codex-only during scoping and left out of the area briefs; it is a **high-severity Claude OAuth bug** and the Area C refutation caught it. `1323df3` was scoped as a single-site fix in `ClaudeAPIService`; it also changes both OAuth token services. Lesson for audit #5: a commit touching `*Codex*` paths may still carry a Claude half, and upstream's commit message names which path is worst — read it before filing.

## 🔴 Port — high

### A1. Menu bar menu icons are invisible on macOS 27 (`ecaa14d`) — high / trivial
**This is live for the user today, not hypothetical.** Verified from Apple's own header on this machine, not from upstream's claim: `MacOSX27.0.sdk/.../AppKit.framework/Headers/NSMenuItem.h:95` — "in macOS 27 and later, AppKit determines the visibility of menu item images, and will typically hide images. Use the `preferredImageVisibility` property with the `.visible` constant…", and `:101` declares `preferredImageVisibility API_AVAILABLE(macos(27.0))`.

`MenuBarUI.swift:336-342` (`setMenuItemIcon`) sets `item.image` and nothing else — byte-identical to upstream's pre-fix shape — and `grep preferredImageVisibility` over the fork returns **zero hits**. All seven icon'd items in the status item's right-click menu funnel through that one function (`MenuBarUI.swift:258, 270, 281, 291, 301, 314, 326`), so all seven are stripped. Account-submenu items set only `item.state` and render via `onStateImage`, so they are unaffected; the fork has no update-badge path (`MenuBarUI.swift:284`), so upstream's second hunk has no counterpart here.

Fix is a two-line helper plus an `#available(macOS 27.0, *)` guard — the guard is **required**, not optional, since the property is `API_AVAILABLE(macos(27.0))` and the deployment target is 26.0.

**Use `ecaa14d`'s typed form, NOT `cedffaa`'s KVC workaround.** `cedffaa` exists only because upstream's release CI is pinned to Xcode 26.6, whose SDK lacks the symbol. The fork's CI is `xcode-version: latest-stable` (`.github/workflows/release.yml:162-165`) and the local toolchain has the symbol. Porting the KVC form would be cargo-culting a constraint the fork doesn't have.

*Caveat kept deliberately:* the header says AppKit "will typically hide" based on "system configuration" — the documented default, not a proof for every configuration. Nobody launched the app and looked. Confirm on screen before claiming a visible before/after.

### A2. A rotated refresh_token can be written to the wrong account (`908f3ce`) — high / small
**Omitted from scoping as Codex-only; it is not.** `ClaudeAPIService.swift:548-556` writes the rotated token via `UserSettings.shared.silentlyUpdateCurrentClaudeSessionToken(newRefresh)`, inside a `DispatchQueue.main.async` — i.e. it targets whichever account is *selected when the callback lands*, not the one that asked for the refresh. Switching accounts inside that window puts account A's new token into account B's entry.

Upstream's message names the Claude OAuth path as the worst case, and the reasoning holds here: refresh_tokens rotate and the server invalidates the old one immediately, so A loses its new token while B has its own overwritten — **both accounts permanently signed out, recoverable only by re-authenticating twice.** Multi-account users only, but the fork has supported multiple accounts since before v1.9.1.

Upstream's fix: locate the account by the token held when the refresh *started*, never by current selection, and drop the write on a miss (a miss means the account was deleted mid-refresh or another refresh already rotated it; "fall back to current" is exactly the wrong answer). Upstream factored this into a pure `AccountTokenRotation` resolver — which would be unit-testable in the fork's SwiftPM target if placed under `Helpers/`.

### A3. A revoked OAuth grant isn't reported as an expired session (`a6b2b83`) — medium-high / small
`ClaudeOAuthService.swift:119-124` is byte-identical to upstream's pre-fix code: it decides grant death from the HTTP status code alone. Anthropic returns RFC 6749 §5.2's **HTTP 400 with `invalid_grant`**, which the fork maps to `httpError(400)`.

Two concrete fork consequences: the re-login prompt at `DataRefreshManager.swift:272-275` only fires on `.sessionExpired`, so it never fires; and `isAuthenticationError(_:)` (`UsageDetailView+Helpers.swift:173-177`) doesn't match `httpError`, so the popover shows no **Go to Settings** button either (consumed at `UsageDetailView.swift:292`). The user is stuck with a dead grant and no offered route back.

Upstream added `Helpers/OAuthGrantFailure.swift` with `isDeadGrant(statusCode:body:)`. Put it under `Helpers/` and register it in `Package.swift` so the predicate is testable; port upstream's `OAuthGrantFailureTests`. *Note:* this also changes the plain-401 mapping from `.unauthorized` to `.sessionExpired` — intended, since only `.sessionExpired` triggers the prompt, but it is a behaviour change beyond the revoked-grant case.

### A4. The request-burst triad (`b1b89f4` + `48a156a`, `1c24bbf`, and the `bypassBackoff` half of `e897012`) — high / trivial-small
Three separate defects that each leave a path open; land them together.

- **Duplicate request on every tier change.** `MenuBarManager.swift:179-186` handles `.refreshIntervalChanged` with `stopRefreshing()` + `startRefreshing()`, and `startRefreshing()` fetches immediately (`DataRefreshManager.swift:283-286`). A smart-mode tier change is posted within a few hundred ms of the fetch that caused it, so every tier transition — and every refresh-mode or interval change — fires a second request. Replace with reschedule-only. *Note:* this leaves `stopRefreshing()` (`:297-300`) with no callers; upstream deleted it.
- **Off-cycle requests don't push the timer back.** `DataRefreshManager.swift:168` records `lastAPIFetchTime` but never reschedules. `restartTimer()` (`:318`) has three call sites — `:286`, `:364`, `:405` — and the latter two are inside `if wasIdle`, so **in active mode neither a manual refresh nor a popover open reschedules the 60s timer**; a manual refresh can be followed seconds later by a tick. Upstream funnels everything through `markRequestIssued(at:)`, which does both.
- **The backoff suppresses the user's own refresh — a fork-only defect, strictly worse than the upstream bug `e897012` fixed.** v1.9.2 put the guard at the very top of the shared choke point (`DataRefreshManager.swift:156-163`), which was the right instinct for *automatic* triggers but also swallows a manual refresh: the user presses refresh during a backoff window and nothing happens, with no feedback. Upstream gates only the automatic triggers (`fetchUsage(bypassBackoff:)`, true from manual refresh). *Caveat:* `bypassBackoff` lets a manual refresh re-trigger a limit the app is waiting out; the only bound is the 10s debounce at `:390-396`, **which is compiled out under `#if !DEBUG`** — check that before relying on it.

## 🟠 Port — medium

### B1. API responses are written to the on-disk URL cache (`1323df3`) — medium / small
All three of the fork's `URLSession`s are built on `URLSessionConfiguration.default`, whose `urlCache` is `URLCache.shared` with a ~2 GB disk capacity: `ClaudeAPIService.swift:50-60` (every usage poll), `DiagnosticManager.swift:69`, and — found by the Area C refutation, not the area itself — `ClaudeOAuthService.swift:92-95` plus a second OAuth site, i.e. **token-endpoint responses too**.

Characterize this accurately rather than dramatically: usage response bodies are percentages and reset times, not credentials. The sharper points are (a) OAuth *token* responses are a different matter, and whether Anthropic sends `Cache-Control: no-store` there is unverified — checking costs a real credential round-trip; (b) `URLCache` stores the `HTTPURLResponse` alongside the body, so response headers are plausibly persisted; and (c) `DiagnosticManager.swift:69` sets **no** `requestCachePolicy` at all, so unlike the other two it can *read* from the cache — a diagnostic run could report a cached response as a live result, which is a correctness bug in the one tool meant to establish ground truth. App Sandbox confines the files to the container but does not stop them being written. The agent could not read the container's Caches directory (no TCC access), so the on-disk claim is from configuration, not observation.

Upstream's `NetworkCachePolicy.swift` adds `URLSessionConfiguration.uncached` (`.default` with `urlCache = nil`, deliberately not `.ephemeral`, which would also drop cookies — and the fork's session-key path **needs** its cookie).

### B2. Menu bar icon colors follow the system theme, not the menu bar (`cc31d63`) — medium / small-medium
The menu bar's lightness follows the wallpaper and is independent of the system Dark/Light setting, so `AppleInterfaceStyle` cannot decide the text color; only the status item's `button.effectiveAppearance` can.

The fork is **half-fixed**, which is why it looks wrong rather than merely imperfect. The correct source already exists — `ColorScheme.swift:22-33`, `isDarkMode(for statusButton:)` — and the circle renderer uses it (`MenuBarIconRenderer.swift:352`). But three shape renderers read `UsageColorScheme.isDarkMode` with no button (`ShapeIconRenderer.swift:156, 341, 465`) while the correct `button` is in scope in the same function, and four backdrop fills are still hardcoded `NSColor.white.withAlphaComponent(0.5)` (`MenuBarIconRenderer.swift:296`, `ShapeIconRenderer.swift:49, 228`, +1).

Worse, the fork has the same cache-staleness bug upstream fixed: `generateCacheKey` (`MenuBarUI.swift:404-428`) does **not** include appearance — and its doc comment at `:31` claims the key is `"mode_style_percentage_appearance"`, which is stale and wrong. Nothing observes menu bar appearance, so even the already-correct line 352 is baked into a cached `NSImage` and won't repaint when the wallpaper flips.

Split this: the wrong-source routing and the backdrop fill are small and safe; the **KVO half is the riskiest edit in this delta** (making `MenuBarUI` an `NSObject`, observing `button.effectiveAppearance` on the status item, and tearing the observer down before dealloc or it crashes). Upstream's 200ms debounce was tuned against its own build — it reports the appearance bouncing ~6 times in a second at creation. Treat the 0.50 → 0.30 alpha drop as a **taste change, not a fix**; it alters how "Color with Background" looks for users who chose it deliberately.

### B3. Nothing backs off on transient failures (`e897012`) — medium / medium
`rateLimitedUntil` is assigned in exactly two places — `:186` (cleared on success) and `:265`, inside `if case UsageError.rateLimited`. So a sustained 5xx, a Cloudflare block, or an offline Mac keeps hitting at `effectiveRefreshInterval` (60s in active mode) **indefinitely**. Upstream backs off on 5xx, network errors and Cloudflare blocks too, with a *lower* cap for network errors precisely because nothing clears the backoff when connectivity returns — keep that 5-minute cap if ported; the fork has no connectivity-restored event either.

Two smaller pieces of the same commit:
- **Retry-After should widen the ladder, not replace it.** `:256-264` lets a positive `Retry-After` overwrite the exponential ladder and writes it back as the new ladder value; upstream takes the *greater* of the two. Also restrict the delta-seconds form to digits only so `inf` / `1e3` / `+5` don't parse (`ClaudeAPIService.swift:74`).
- **A cancelled request is counted as a failure.** `ClaudeAPIService.swift:113` cancels the in-flight task at the head of every fetch, and `:202-205` maps any `URLSession` error — cancellation included — to `networkError`. **Only `:202` is affected**: the refutation established that `currentTask` is assigned solely at `:201` in `fetchMainUsage`, so the OAuth site at `:594` is *not* reachable this way. Audit #3's habit of listing both paths led the area astray here.

### B4. An account switch doesn't clear the backoff — medium / trivial
A rate limit belongs to the token, not the app, so switching accounts should reset it. `prepareForAccountSwitch()` (`DataRefreshManager.swift:146-154`) clears the stale-data latch added in v1.9.3 but leaves `rateLimitedUntil` and `rateLimitBackoff` untouched, so a fresh account inherits the previous one's suppression window.

⚠️ **The area's proposed edit for this was a no-op** — it added three comment lines and never assigned anything. Caught by the refutation. Whoever lands it must actually clear both fields.

### B5. The onboarding flow breaks a successful sign-in (`4ec7b6c`) — medium / medium
The fork **does** have an onboarding flow (`Views/Settings/Welcome/WelcomeView.swift`) and it carries upstream's bug exactly: `WelcomeView.swift:293-298` takes the `Account.sessionKey` returned by browser login — an OAuth **refresh token** — and feeds it to `fetchOrganizations` as if it were a cookie. That request always fails, so a *successful* sign-in ends with "failed to fetch organization ID". Severity was downgraded from high by the refutation: `.accountChanged` already triggers a fetch, so the user is not left with no data, just a spurious error.

Trivial second half of the same commit: the onboarding and OAuth windows are `.floating` (`WebLoginWindowManager.swift:48`, `ClaudeUsageMonitorApp.swift:112`), so they draw above every other app **including the browser they are telling the user to go to**. Making them ordinary windows is a one-line change each and matters more here than upstream, since the fork's OAuth flow is explicitly a system-browser flow.

## 🟢 Port — low

- **`7a227ce` launch-at-login shows a red error before first registration** — trivial. `SMAppService.Status.notFound` is the normal state before `register()` has ever been called, but the fork renders it as a red `xmark.circle.fill` / "Not Found" (`GeneralSettingsView.swift:634-635, 651-652, 668-669`). Fold it in with `.notRegistered` ("Disabled"). 9 one-line edits: three case merges, one accessor deletion (`LocalizationHelper.swift:399`), and one string removed from each of the 5 locales (all at `:191`). It misreports as an *error*, not as enabled. *Unverified:* that `.notFound` really is the pre-registration state comes from upstream's commit message, not from observation here.
- **`cedffaa`'s CI half** — trivial, and unrelated to the KVC change. `build.sh:183` sends all `xcodebuild` output to `build.log` (`:219, 274, 339, 407`), and `release.yml:219` calls it with no failure handler, so a CI compile failure surfaces as a bare "exit code 65" with the cause invisible. Add upstream's `if: failure()` step that tails the log. Cheap insurance given the fork's CI pins `latest-stable`, which the runner image resolves — nothing in the repo controls which Xcode that yields.
- **`cc31d63`'s string half** — the fork still ships the obsolete advice telling users to switch to "Color with Background" when "Color Translucent" fails on dark wallpapers (`en.lproj:70-71` and the 4 other locales), which stops being true once B2 lands.
- **`5a60f17` menu bar icon size setting** — low / medium, and genuinely conflict-free: with comments stripped, the fork's `ShapeIconRenderer` differs from upstream's pre-commit version by only 81 lines, all of them the fork's own additive divergences. ⚠️ Three of the area's twelve edit sites are wrong or missing, and `GeneralSettingsDisplaySection.swift` does not exist in the fork. Re-derive the sites if porting.
- **`72c23d5` debug gating** — `PARTIAL`, and **DEBUG builds only**. The area labelled the fork `NOT_AFFECTED` while proposing seven edit sites; the refutation corrected it to `AFFECTED (DEBUG only)`. Nothing debug-only is reachable in a Release build — all twelve debug properties sit inside `#if DEBUG` (`UserSettings.swift:553+`). Optional cleanup, not a security item.

## ⏸️ Partial — larger, defer unless wanted

- **`639cb48` customizable notification thresholds** — medium / large. The fork's thresholds are three hardcoded constants (`NotificationManager.swift:24, 27, 30`); upstream replaced them with a configurable range (50…100 step 5) and decoupled reset detection from the warning threshold. Any port **must preserve the fork's per-account dedup** keyed `"<accountId>:<limitType>"` (v1.9.1) — that is a fork divergence upstream doesn't have.
- **`cc764d9` used/remaining toggle doesn't reach the menu bar** — medium / large. Real bug, present identically: the toggle is view-local (`UsageDetailView.swift:63, 67`, written at `:548-550`) so it never reaches the menu bar icon. Upstream's fix is entangled with its own spring-animation rework; the fork could take just the state move.

## ✅ Skip / product decisions

- **Pace Graph** (`abf8097`, `fec32d4`, `29573e7`, `eb6a8c4`, `c78e700`, `9e31a42`, `e5b4849`, `3a6d415`) — v3.5.0's headline feature, ~1,300 lines across ~18 files. A second popover visualization plotting each limit against an "ideal pace" line. Purely a product decision; no defect behind it.
- **`67232bb` five-tab settings reorganization** — large refactor with no bug behind it. Note it **supersedes upstream's own `92223a2`**, the layout fix the fork ported in v1.9.3; the fork's version stands on its own.
- **`7a8b023` unified logging** — `PRODUCT_DECISION`, medium / large. One auditable logging system replacing two parallel loggers, with an expanded `SensitiveDataRedactor`. Worth considering *if* the fork ever does the OAuth-aware diagnostics below, since the two overlap.
- **`90ae544` auth-path-aware diagnostics** — `PARTIAL`, high value but **large**. The fork's diagnostic has **no auth-path awareness at all**: `grep -i oauth` over `DiagnosticsView.swift`, `DiagnosticManager.swift` and `DiagnosticReport.swift` returns zero hits, and `runDiagnosticTest()` (`DiagnosticManager.swift:37-66`) branches only on `hasValidCredentials`. For an OAuth account it reports redacted `organizationId` / `sessionKey` fields that mean nothing. Upstream's version is built on a `ProviderType`/`ProviderAuthPath` abstraction the fork never had, so this is a rewrite, not a port. ⚠️ Also note upstream's approach makes the diagnostic trigger a **real token refresh**, which — because refresh_tokens are single-use and rotate — means running diagnostics mutates stored credentials as a side effect.
- **`14b364d` transient-error header indicator** — decline the redesign; the fork's v1.9.3 stale-data banner already solves the same user problem. But the refutation corrected the blanket `SKIP`: **take upstream's last-fetched timestamp**, and note its actual objection was the *popover window jumping in size* — which the fork's banner also does, by 47–53pt (`UsageDetailView.swift:112-114`, `:120` feeding the fixed frame at `:635`). That is the open field-watch item from v1.9.3, now with upstream's independent judgement that the jump itself is the problem.
- **`d72a0fc` ring-toggle stray marks** — omitted from scoping, flagged by the refutation as a likely small `PARTIAL`: the fork strokes a raw `Circle().trim` with `lineCap: .round` under the same spring (`UsageDetailView.swift:370-382`, `:425`) with no minimum-arc guard, so the zero-length-arc dot artifact is plausible here too. Not verified on screen.
- Everything Codex — token/Keychain handling, credit balance, reset announcements, the hexagon badge hunks of `cc31d63` — and the website rebuild and localization commits.

## Not from upstream: Swift 6 readiness

Surfaced while confirming the fork builds under Xcode 27.1, so recording it here rather than losing it. The tree carries warnings that are **hard errors in the Swift 6 language mode**: `UsageHistoryStore.swift:50, 66` (`reference to captured var 'self' in concurrently-executing code`), `:126` and `ClaudeAPIResponseModels.swift:197` (MainActor-isolated calls from nonisolated contexts — the latter because `UsageData` is `Sendable` but not `nonisolated`, pre-existing and merely relocated by v1.9.3), plus deprecated `onChange(of:perform:)` in three views. None bite today. This is the same hazard class the `OAuthCallbackServer` deinit comment warned about in v1.9.3.
