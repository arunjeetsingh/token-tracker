# Decision Log

Append-only. Newest at top.

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
