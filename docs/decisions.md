# Decision Log

Append-only. Newest at top.

---

## 2026-05-26 — ADR-013: Android client = native Kotlin + Compose, monorepo, applicationId `studio.maximumimpact.tokencounter`

**Context:** Per ADR-001 (iOS first, then Android), now starting Android development. New domain `maximumimpact.studio` will be the canonical reverse-domain prefix for all future Maximum Impact apps.

**Decision:**
  - Native Kotlin + Jetpack Compose (no Flutter, no React Native, no KMP-shared-UI).
  - Monorepo with iOS — Android lives under `android/` in this repo. Per-platform CI workflows gated by `paths:` filter so cross-platform PRs don't trigger noisy builds.
  - applicationId: `studio.maximumimpact.tokencounter`. Frozen forever (Play Store treats it as the primary key).
  - Visual language: matches iOS for v1 (white background, #007AFF blue accent, bold display number). Will revisit Material You / dynamic color after launch.

**Alternatives considered:**
  - **Separate `tokencounter-android` repo** — rejected: duplicates docs/ADRs/icon, drift risk between platforms.
  - **Flutter or React Native** — rejected per ADR-001.
  - **KMP shared business logic** — deferred. Worth considering after both apps stabilize, but adds toolchain complexity for an MVP.
  - **applicationId `ai.openclaw.tokencounter`** — rejected: openclaw is the agent platform, not the studio. maximumimpact.studio is the long-term brand.

---

## 2026-05-26 — ADR-012: User-facing name = "TokenCounter" (no space)

**Context:** Shipped the v1.0.x builds with `CFBundleDisplayName: Token Counter` (two words). The iOS Home Screen has a fixed icon-label width and strips the space, rendering the label as "TokenCounter" anyway. So the App Store listing, the docs, and the marketing site said "Token Counter," but every actual iPhone Home Screen running the app said "TokenCounter." Internally inconsistent across the surfaces a user sees.

**Options considered:**
  - **A:** Pick a shorter user-facing name that fits with the space intact (e.g. "Tally", "Burn"). Avoids the rendering issue entirely but throws away the "Token" + "Counter" search terms we already optimized the App Store keywords around, and forces a fresh naming exercise.
  - **B:** Keep "Token Counter" everywhere and accept that the Home Screen disagrees with the Store listing. Cheapest, but it's a visible inconsistency every time a user installs and the icon label doesn't match what they tapped Install on.
  - **C:** Lean in. Make "TokenCounter" (no space) the canonical name across the app's display name, the App Store listing, and all docs. The Home Screen already renders it that way; align everything else with that reality.

**Decision:** Option C. `CFBundleDisplayName` becomes `TokenCounter`. App Store Connect listing copy, privacy policy, GitHub Pages site, marketing screenshot captions, and in-app UI strings (header, onboarding) all use "TokenCounter" as one word. Bundle ID (`ai.openclaw.tokentracker.TokenTracker`), Xcode target name (`TokenTracker`), repo name (`token-tracker`), Swift type/file/directory names, and the GitHub Pages URL slug all stay unchanged — those are internal/frozen identifiers, not user-facing.

**Tradeoffs accepted:**
  - Past ADRs (and any old release notes that already shipped) still say "Token Counter." We don't retroactively rewrite history; we just stop creating new instances of the two-word form.
  - App Store Connect screenshots from earlier builds show the two-word name in chrome we burned into the captioned PNGs. Regenerated in the same PR as the rename.
  - The subtitle "Anthropic spend at a glance" stays as-is — it's a tagline, not the name.

---

## 2026-05-26 — ADR-011: Dashboard hero composition (sparkline + top models)

**Context:** The v0.2 dashboard rendered as one giant MTD dollar figure floating in white space. PR #23's commit message explicitly flagged this as "mostly empty space" for the App Store hero shot. The screen needs more visual interest — both for marketing and as a real product, because power users want some sense of trend and where the money is going, not just "$X this month."

**Options considered:**
  - **A:** Today-vs-yesterday delta pill ("+12% vs yesterday"). Cheap to build, but a single number doesn't fill the empty space and isn't differentiated — every finance app has this.
  - **B:** Full chart with axes, legend, multiple series, time-range picker. Substantial UI work and visually heavy; clashes with the app's minimalist single-number aesthetic.
  - **C:** Drop in a charts library (Swift Charts or third-party). Adds a dependency and pulls in axis/legend chrome we'd then need to hide.
  - **D:** Stocks-app-style sparkline (no axes, no labels) + small top-3 models breakdown list. Information-dense, native SwiftUI `Path`, no dependency, matches the existing visual restraint.

**Decision:** Option D. A 30-day finalized-spend sparkline sits below the hero number with a "Last 30 days" caption, followed by a "TOP MODELS" section listing the three highest-cost models month-to-date in iOS Settings-style rows. Both are populated from the same single `cost_report` call (now grouped by model) — no extra network round-trips, no extra battery.

**Implementation notes:**
  - `AnthropicClient.costDetail(start:end:)` is the new single source of truth; both `monthToDateCost` and `totalCost` route through it.
  - The sparkline window is the trailing 30 days, even when MTD only covers a few days. That's deliberate: users early in the month would otherwise see a 3-point chart, which looks broken.
  - Today is intentionally excluded from the sparkline. It's the intraday estimate; folding it in would swing the last point wildly throughout the day.
  - Model breakdown is in-month only, matching the hero number's scope.
  - Display-name parsing (`claude-opus-4-7` -> `Claude Opus 4.7`) lives next to the client; unknown ids fall through unchanged so the UI never drops a row silently.

**Tradeoffs accepted:**
  - One additional query parameter (`group_by[]=model`) on the cost_report call. Anthropic's API already returns this shape; we just ask for the splits.
  - Sparkline auto-scales y-axis per render; absolute spending levels aren't comparable across screenshots. That's fine — it's a trend indicator, not a measuring tape.
  - If a user has fewer than 2 days of data, the sparkline falls back to a placeholder rounded rectangle instead of crashing or showing a single dot. The top-models block hides entirely on empty data.

---

## 2026-05-26 — ADR-010: Caption overlay strategy for App Store screenshots

**Context:** Apple App Store screenshots benefit from editorial captions — a short headline that tells the prospect what the screen does before they read the UI. We have two reviewer-grade screenshots (dashboard, onboarding) captured at the two required sizes (6.9" 1320×2868 and 6.5" 1242×2688). The dashboard has a generous top white zone; the onboarding has very little.

**Options considered:**
  - **A:** Full marketing mockup — phone frame around the screenshot, colored gradient background, custom display font, wordmark, app icon. The Headspace / Things 3 / Duolingo treatment.
  - **B:** Overlay-on-screenshot — leave the screenshot exactly as-is, render a headline + subhead directly into the existing empty top space in plain SF Pro. No phone frame, no background, no chrome.
  - **C:** Ship the raw screenshots with no captions at all.

**Decision:** Option B. Implemented in `scripts/add-caption-overlays.py` as a deterministic Python + Pillow pass over the freshly-captured PNGs. The script auto-detects the topmost clean-white horizontal band of sufficient height below the iOS status bar and places the caption block there with breathing room, so it never collides with app chrome (gear icons, nav title, large title). Output lands in `docs/app-store-screenshots/{6.5inch,6.9inch}/captioned/`.

**Why B over A:** Faster to iterate (no design tool round-trip), lower design risk (a bad mockup looks worse than a clean screenshot), and a plain editorial caption matches the app's minimalist aesthetic. We can upgrade to A later without throwing away the screenshot pipeline. Why B over C: Apple's own merchandising shelves prefer screenshots that read at a glance — a one-line headline meaningfully improves install-decision quality.

**Tradeoff accepted:** Captions are static PNG burns, not live App Store Connect localizations. If we add Spanish/French we'll need to re-run the script with localized copy and upload a second set, or move to A.

---

## 2026-05-26 — ADR-009: Demo Mode for App Reviewers via magic key string

**Context:** App Store review requires reviewers to exercise the full app. TokenCounter's full UI depends on a live Anthropic Admin API key against a real organizational account — something Apple Reviewers won't (and shouldn't have to) provision. v0.2 shipped without a story here; the listing's "Review notes" section had a TBD.

**Options considered:**
  - **A:** Stand up a low-scope demo Anthropic organization, mint a real Admin key with read-only Cost/Usage scopes, paste it into App Store Connect's "Demo Account" field. Real network paths, but: (i) Anthropic doesn't actually offer scoped-down admin keys (admin = full org read/write), (ii) every reviewer using the same key risks accidental key exposure, (iii) requires us to maintain billing on a demo org indefinitely.
  - **B:** Embed a magic key string in the app. When the reviewer pastes it during onboarding, the app short-circuits to Demo Mode against canned data, with a visible "DEMO" indicator. Persists across relaunch (App Review will kill+relaunch). Clears on Disconnect.
  - **C:** Ship a separate "reviewer build" via TestFlight that hardcodes demo mode. Forks the build matrix and risks the wrong build landing on the App Store.

**Decision:** Option B. Magic key value embedded in source as `DemoMode.appReviewKey`. Format `sk-ant-demo-YYYY-MM-wWW` so we can rotate per release iteration if it ever leaks. Persisted in `UserDefaults` (not Keychain — demo state, not a credential). A small "DEMO" pill in the dashboard nav bar makes the mode unambiguous to Apple's reviewers and to ourselves.

**Why B over A:** Zero infrastructure, zero recurring cost, no real key can leak, and the demo data is deterministic across reviewers — which makes the experience reviewable in the first place.

**Risk accepted:** A determined user could decompile the IPA and find the magic string, then activate demo mode locally. That's harmless — demo mode shows canned data and reaches no network. Rotation per release is just hygiene.

**Compatibility:** Existing launch-arg-driven `DemoMode` (used by the screenshot capture script) is untouched. `isEnabled` now returns true for either entry point. Disconnect clears the persisted flag before falling through to the existing Keychain-wipe path.

---

## 2026-05-24 — ADR-008: Onboarding UX = polished admin-key paste (Option B), not cookie scraping

**Context:** First TestFlight build (v0.1.0) shipped with a bare SecureField asking for an admin key — zero context, scary. Three real paths to better UX:
  - **A:** Reverse-engineer `console.anthropic.com` session cookies via WebView. True "just log in" UX but uses undocumented APIs; near-certain App Store rejection + ToS risk.
  - **B:** Keep admin-key model, wrap it in a great 3-step onboarding (in-app Safari → console → paste with clipboard auto-detect). Official API, stable, App Store safe.
  - **C:** Build a backend that holds keys server-side; phone gets a session token. Right destination for a public product, but turns the MVP into a 3-week side quest and makes us custodians of other people's admin keys.

**Decision:** Option B for now. Path to C stays open — the iOS `AnthropicClient` is the only place that knows about `api.anthropic.com`, so swapping it for our own backend later is a localized change.

**Shipped in this PR (v0.2.0):**
  - `OnboardingView` with 3 step cards + in-app `SFSafariViewController` for the console.
  - Clipboard auto-detect for `sk-ant-…` prefixes (peek-only, no system banner unless we surface the suggestion).
  - Show/hide toggle on the SecureField.
  - Pre-flight `whoami()` call before saving to Keychain — junk keys never get persisted.
  - `SettingsView` (gear in toolbar) with masked key, org name, and Disconnect (wipes Keychain, returns to onboarding).
  - Auto-recover on 401/403: stale keys get wiped and the user is bounced to onboarding instead of a generic error.

**Explicitly NOT shipped:** OAuth/cookie scraping (Option A) and any server-side key custody (Option C).

---

## 2026-05-23 — ADR-007: XcodeGen owns the `.xcodeproj`

**Context:** `.xcodeproj/project.pbxproj` is a multi-thousand-line auto-generated UUID-keyed file that conflicts on every PR. We want PR diffs that read cleanly.

**Decision:** The Xcode project is generated from `ios/project.yml` via [XcodeGen](https://github.com/yonaskolb/XcodeGen). `ios/TokenTracker.xcodeproj/` is gitignored. CI runs `xcodegen generate` before `xcodebuild`.

**Tradeoffs:**
- Everyone needs `brew install xcodegen` once.
- Custom Xcode UI changes (build phases, capabilities) must be reflected back into `project.yml` instead of being committed via the IDE.

## 2026-05-23 — ADR-006: PR-only via local pre-push hook

**Context:** GitHub free tier blocks branch protection on private repos. We still want PR-only flow.

**Decision:** Self-enforce with a tracked pre-push hook at `scripts/git-hooks/pre-push` that rejects pushes to `main`. New clones run `./scripts/install-git-hooks.sh` once. Emergency override via `git push --no-verify origin main`.

**Risk accepted:** A clone that skips the hook install can still push to main. Mitigation: we are the only collaborator and the convention is documented in README.

---

## 2026-05-23 — ADR-005: `amount` field is in cents USD, not dollars

**Context:** First call to `/v1/organizations/cost_report` returned `{"amount":"2013.9595","currency":"USD"}`. The `currency` field misleadingly suggests `amount` is in dollars. MTD total summed to $56,073.44 vs dashboard's $562.03 — exactly 100x off.

**Decision:** All `amount` values from the cost_report endpoint must be divided by 100 to convert from cents to dollars. Wrap in a typed `Money` value type in the iOS app so the conversion only happens once. Add a unit test that locks the contract.

**Source:** Confirmed via web search + empirical validation against Arun's dashboard. Anthropic API docs do not state this explicitly — risk that they change it later.

---

## 2026-05-23 — ADR-004: Repo name = `token-tracker`

**Decision:** Private GitHub repo `arunjeetsingh/token-tracker`. No org. Main branch protected. PR-only after first push. Squash merge (clean linear history).

---

## 2026-05-23 — ADR-003: Backend pattern = none for MVP

**Context:** Admin API key is highly sensitive (full read/write to org). Two choices:
1. Store key in iOS Keychain, call Anthropic API directly from the device.
2. Run a tiny backend service that holds the key, exposes a narrow read-only endpoint.

**Decision (MVP):** Option 1 — direct from device, key in Keychain. Simpler, no infra to maintain. Single-user app, key only ever lives on Arun's device.

**Future:** If we add multi-user / sharing / push notifications, move to option 2 with a proper auth layer.

**Risk:** If the phone is compromised, the admin key (which has org-wide read-write scope) is exposed. Anthropic only offers admin keys, no read-only variant. Mitigations: Keychain w/ `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, never sync to iCloud Keychain, require Face ID / passcode to read on each app launch.

---

## 2026-05-23 — ADR-002: Convert Anthropic account to organization

**Context:** Anthropic's Usage & Cost Admin API requires an Admin API key, which is only available to organization accounts (not individual).

**Decision:** Arun converted his individual account to an org ("Maximum Impact"). Admin key generated.

**Tradeoff:** None observed — billing, pricing, and feature access unchanged. Org wrapper is purely structural.

---

## 2026-05-23 — ADR-001: iOS first, then Android, then web

**Context:** Project goals (per Arun, 2026-05-22): build native apps, MVP on iOS, expand later.

**Decision:** Native SwiftUI iOS app. No React Native, no Flutter. Re-implement on Kotlin/Compose for Android. Web is undecided — possibly Next.js, possibly skipped if mobile is enough.

**Why native:** Better Keychain integration, smoother UX, takes advantage of Arun's MacBook Air + Mac mini Apple ecosystem for dev. Cross-platform frameworks add complexity we don't need for a single-purpose tracker.
