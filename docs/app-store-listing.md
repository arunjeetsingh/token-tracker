# App Store Connect listing — Token Counter

Source of truth for everything we copy/paste into App Store Connect.

## Identity

| Field | Value |
| --- | --- |
| App name | **Token Counter** |
| Subtitle | _Anthropic spend at a glance_ |
| Bundle ID | `ai.openclaw.tokentracker.TokenTracker` |
| SKU | `tokencounter-ios-1` |
| Primary category | **Developer Tools** |
| Secondary category | **Productivity** |
| Age rating | **4+** (no objectionable content) |
| Price | **Free** |

## Promotional text (max 170 chars)

> Track your Anthropic API spend in real time. Month-to-date plus today's intra-day estimate, fetched straight from Anthropic — no server, no account, no analytics.

(159 chars)

## Description (max 4000 chars)

> Token Counter is the simplest way to keep tabs on what your Anthropic API account is costing this month — without giving up your privacy.
>
> Paste your Admin API key once, and the app fetches live cost data straight from Anthropic to your iPhone. You'll see:
>
> • Month-to-date spend across your whole organization
> • Today's intra-day cost estimate (Anthropic's daily report only closes yesterday's bucket; we add a token-priced estimate of today)
> • Breakdown by model
> • Quick visual sense of whether you're under, on track, or over your usual monthly burn
>
> Token Counter does not have a server. The app talks directly from your iPhone to api.anthropic.com using your key. Nothing about your account, key, usage, or cost ever passes through any third party — including us.
>
> WHY YOU'LL LIKE IT
>
> • No account to create.
> • No analytics, no crash reporting, no advertising SDKs, no third-party trackers. Zero.
> • Your Admin API key is stored only in the iOS Keychain on this device, protected by Face ID / Touch ID / your passcode.
> • One-tap "Disconnect" in Settings wipes the key from Keychain.
> • Native SwiftUI, no web views for data, no bloated frameworks.
>
> WHAT YOU NEED
>
> Token Counter reads from Anthropic's Admin API, which requires:
>
> 1. An organizational Anthropic account (admin keys aren't available on individual accounts).
> 2. An Admin API key (the ones that start with `***-…`, not `***-…`).
>
> The onboarding flow walks you through creating both. If you already have them, it's about 30 seconds to be up and running.
>
> WHO IT'S FOR
>
> Developers, founders, and ML engineers who use Anthropic's API every day and want a fast way to check spend without logging into the Console on the web. Especially useful if you're testing prompts that could rack up cost quickly and you want a glanceable number on your home screen.
>
> PRIVACY
>
> See [arunjeetsingh.github.io/token-tracker/privacy](https://arunjeetsingh.github.io/token-tracker/privacy/) for the full policy. TL;DR: we don't collect any data because we have nowhere to put it.

## Keywords (max 100 chars, comma-separated)

```
anthropic,claude,api,token,cost,spend,monitor,llm,ai,billing,usage,tracker
```

(80 chars)

## Support URL

`https://github.com/arunjeetsingh/token-tracker/issues`

## Marketing URL

`https://arunjeetsingh.github.io/token-tracker/`

## Privacy Policy URL

`https://arunjeetsingh.github.io/token-tracker/privacy/`

## What's New (release notes for v1.0.x — first public release)

> First public release of Token Counter.
>
> • Live month-to-date Anthropic spend
> • Today's intra-day cost estimate
> • By-model breakdown
> • No server, no account, no analytics — your admin key never leaves your device

## App Privacy (data collection questionnaire)

Every section answered as **"Data Not Collected"**.

We do not collect:

- Contact Info, Health & Fitness, Financial Info, Location, Sensitive Info, Contacts, User Content, Browsing History, Search History, Identifiers, Purchases, Usage Data, Diagnostics, or Other Data.

The Anthropic Admin API key is **stored only on the user's device** (iOS Keychain) and **sent only to api.anthropic.com**. Under App Privacy guidelines, data that is not transmitted off-device and not received by a third party we work with is not "collected."

## Export compliance

`ITSAppUsesNonExemptEncryption = false` is set in `Info.plist`. The app uses only Apple's standard HTTPS/TLS, which qualifies for the standard encryption exemption.

## Screenshot plan

- 6.7" (iPhone 17 Pro Max simulator) — 1290 × 2796 — required
- 6.5" (iPhone 11 Pro Max-class) — 1242 × 2688 — required for back-compat
- Capture: Today's cost view, MTD view, model breakdown, onboarding step 2 (Admin Keys page), Settings

Caption ideas (top of each screenshot, App Store overlay style):

1. "How much am I spending this month?"
2. "Track today's cost in real time"
3. "Break it down by model"
4. "Your key never leaves your phone"
5. "30-second setup. No account."

## Review notes (App Review demo account / instructions field)

> **Demo Mode for App Review**
>
> Token Counter is a thin client for the Anthropic API. The full experience requires an Anthropic organization Admin API key, which Apple Reviewers won't have. To exercise the full UI without a real Anthropic account, we've provided a **Demo Mode** activated by a magic key:
>
> 1. Launch Token Counter.
> 2. Tap through onboarding to the "Paste your Admin key" step.
> 3. Paste: `sk-ant-demo-2026-05-w22`
> 4. Tap Connect.
>
> The app will switch to Demo Mode (a small "DEMO" pill is visible in the dashboard nav bar), showing a canned month-to-date cost report with realistic numbers. Demo Mode persists across app launches. To exit, tap the gear icon → Disconnect.
>
> Demo Mode is implemented entirely client-side and reaches no network. The real network code paths (Anthropic API, Keychain storage) are exercised when a reviewer chooses to paste a real Admin key instead.
