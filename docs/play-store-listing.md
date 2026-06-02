# Google Play Console listing — TokenCounter (Android)

Source of truth for everything we copy/paste into Google Play Console.
Mirrors `app-store-listing.md` (iOS) but adapted to Play's fields, limits, and forms.

## Identity

| Field | Value |
| --- | --- |
| App name (max 30 chars) | **TokenCounter** |
| Package name | `studio.maximumimpact.tokencounter` |
| Developer name | **Maximum Impact Studio** |
| Default language | **English (United States) – en-US** |
| App or game | **App** |
| Free or paid | **Free** |
| Category | **Tools** (alt: Productivity) |
| Tags | API tools, Developer tools, Productivity |
| Contains ads | **No** |
| In-app purchases | **No** |

## Short description (max 80 chars)

> Live Anthropic API spend on your phone. No server, no account, no tracking.

(75 chars)

## Full description (max 4000 chars)

> TokenCounter is the simplest way to keep tabs on what your Anthropic API account is costing this month — without giving up your privacy.
>
> Paste your Admin API key once, and the app fetches live cost data straight from Anthropic to your phone. You'll see:
>
> • Month-to-date spend across your whole organization
> • Today's intra-day cost estimate (Anthropic's daily report only closes yesterday's bucket; we add a token-priced estimate of today)
> • Breakdown by model
> • A quick visual sense of whether you're under, on track, or over your usual monthly burn
>
> TokenCounter does not have a server. The app talks directly from your phone to api.anthropic.com using your key. Nothing about your account, key, usage, or cost ever passes through any third party — including us.
>
> WHY YOU'LL LIKE IT
>
> • No account to create.
> • No analytics, no crash reporting, no advertising SDKs, no third-party trackers. Zero.
> • Your Admin API key is stored only in the Android Keystore on this device, protected by your device biometrics / screen lock.
> • One-tap "Disconnect" in Settings wipes the key from secure storage.
> • Native Jetpack Compose, no web views for data, no bloated frameworks.
>
> WHAT YOU NEED
>
> TokenCounter reads from Anthropic's Admin API, which requires:
>
> 1. An organizational Anthropic account (admin keys aren't available on individual accounts).
> 2. An Admin API key (the ones that start with sk-ant-admin…, not the standard sk-ant-api… keys).
>
> The onboarding flow walks you through creating both. If you already have them, it's about 30 seconds to be up and running.
>
> WHO IT'S FOR
>
> Developers, founders, and ML engineers who use Anthropic's API every day and want a fast way to check spend without logging into the Console on the web. Especially useful if you're testing prompts that could rack up cost quickly and you want a glanceable number.
>
> PRIVACY
>
> See arunjeetsingh.github.io/token-tracker/privacy for the full policy. TL;DR: we don't collect any data because we have nowhere to put it.

## Graphic assets (specs — to produce)

| Asset | Spec | Required | Status |
| --- | --- | --- | --- |
| App icon | 512 × 512 PNG, 32-bit, < 1 MB | ✅ Required | ✅ DONE — `docs/play-store-assets/icon-512.png` (from iOS icon) |
| Feature graphic | 1024 × 500 PNG/JPG (no alpha) | ✅ Required | ✅ DONE — `docs/play-store-assets/feature-graphic.png` |
| Phone screenshots | 2–8 imgs, 16:9 or 9:16, 320–3840 px/side, PNG/JPG | ✅ Min 2 | ✅ DONE — 2× real Android (emulator, demo mode) captioned, `docs/play-store-assets/screenshots/` (1080×1920) |
| 7" tablet screenshots | optional | ❌ | skip (phone-only focus) |
| 10" tablet screenshots | optional | ❌ | skip |

Note: Play feature graphic has no iOS equivalent — made fresh (navy + icon + wordmark).
Screenshots are REAL Android captures from a Pixel-6 emulator running the
debug APK in Demo Mode (`sk-ant-demo-2026-05-w22`), then framed on a clean
1080×1920 canvas with the same iOS caption copy. Regenerate via
`scripts/make-play-assets.py` (reads raw captures from
`docs/play-store-assets/android-raw/`).

**Also backed up to Google Drive** (folder "Play Store assets - TokenCounter",
id `1xIf0odeIkiG8Yc4ZNEvQKZVlUMLxQhdE`): icon-512, feature-graphic-1024x500,
screenshot-01-dashboard, screenshot-02-onboarding.

## Screenshot captions (reuse from iOS)

| Screenshot | Headline | Subhead |
| --- | --- | --- |
| 01-dashboard | How much am I spending? | Live Anthropic API costs, on your phone |
| 02-onboarding | 30-second setup | No account. No server. No tracking. |

Suggested screens to capture (Android emulator, Pixel-class):
Today's cost view, MTD view, model breakdown, onboarding Admin Keys step, Settings.

## URLs

| Field | Value |
| --- | --- |
| Privacy policy (required) | `https://arunjeetsingh.github.io/token-tracker/privacy/` |
| Website (Store listing contact) | `https://arunjeetsingh.github.io/token-tracker/` |
| Support email (required) | `chintu.bot.arun@gmail.com` |
| Support phone | (optional — leave blank) |

## Content rating questionnaire (IARC)

Category for questionnaire: **Utility, Productivity, Communication, or Other**.

Answer all of the following **No / None**:

- Violence, scary or disturbing content — **None**
- Sexual or nudity content — **None**
- Profanity or crude humor — **None**
- Drugs, alcohol, tobacco references — **None**
- Gambling / simulated gambling — **None**
- User-to-user communication / sharing — **None**
- Shares user location — **No**
- Allows purchase of digital goods — **No**
- Unrestricted internet access (e.g. open browser) — **No**

Expected result: rated **Everyone / PEGI 3 / 4+** — for all ages.

## Target audience & content

| Field | Value |
| --- | --- |
| Target age groups | **18 and over** (developer tool; not directed at children) |
| Appeals to children | **No** |
| Ads to children | N/A (no ads) |

This keeps us out of the Families/Designed-for-Families program and its extra requirements.

## Data safety form (Play's privacy declaration)

This is Play's analog to iOS App Privacy. Declare:

**Does your app collect or share any of the required user data types?** → **No.**

Justification (same logic as iOS "Data Not Collected"):
- No data is transmitted off-device to us or any third party we work with.
- The Anthropic Admin API key is stored only on-device (Android Keystore) and sent only to `api.anthropic.com`, which is the user's chosen service provider, not our backend.
- No analytics, crash reporting, ads, or tracking SDKs.

If the form forces a "data transferred" question about the API key:
- The key is **not collected by us**. It is end-to-end between the user's device and Anthropic.
- **Encryption in transit:** Yes (HTTPS/TLS to api.anthropic.com).
- **Data deletion:** User can delete on-device key via Settings → Disconnect. No server-side data exists to delete.

**Security practices:**
- Data encrypted in transit — **Yes**
- User can request data deletion — **Yes (on-device, one tap)**

## App access / review instructions (for Play review)

Play review needs to exercise the app without a real Anthropic Admin key. Provide the same Demo Mode instructions as iOS:

> **Demo Mode for review**
>
> TokenCounter is a thin client for the Anthropic API and normally requires an organization Admin API key, which reviewers won't have. To exercise the full UI:
>
> 1. Launch TokenCounter.
> 2. Tap through onboarding to the "Paste your Admin key" step.
> 3. Paste: `sk-ant-demo-2026-05-w22`
> 4. Tap Connect.
>
> The app switches to Demo Mode (a "DEMO" pill shows in the dashboard) with a canned, realistic month-to-date cost report. It persists across launches; exit via Settings → Disconnect. Demo Mode is fully client-side and reaches no network.

Set under **App access** → "All or some functionality is restricted" → add the above as the instruction, no login credentials needed.

## Ads declaration

**This app contains ads:** **No.**

## Government / financial / health declarations

- Government app — **No**
- Financial features — **No** (it displays the user's own API spend; it is not a financial product, doesn't handle payments, banking, or crypto)
- Health — **No**

## Release tracks

| Track | Status |
| --- | --- |
| Internal testing | ✅ Live (v0.1.1, auto-upload via `android-release.yml` verified) |
| Closed testing | not started |
| Open testing | not started |
| Production | gated on this listing + forms complete |

Auto-upload publishes to **internal** by default; bump the `android-release.yml`
track input to promote to closed/open/production.

## Pre-launch checklist (what's left before Production)

- [x] 512×512 app icon generated (`docs/play-store-assets/icon-512.png`)
- [x] 1024×500 feature graphic created (`docs/play-store-assets/feature-graphic.png`)
- [x] ≥2 phone screenshots (captioned, real Android) generated (`docs/play-store-assets/screenshots/`)
- [ ] Upload the above 4 assets into Play Console (files ready + on Drive)
- [ ] Short + full description pasted
- [ ] Content rating questionnaire submitted → rating received
- [ ] Data safety form submitted (No data collected)
- [ ] Target audience set (18+)
- [ ] App access / Demo Mode instructions added
- [ ] Privacy policy URL set
- [x] Support email confirmed + set (`chintu.bot.arun@gmail.com`)
- [ ] Ads declaration = No
- [ ] Promote a release to Production track
