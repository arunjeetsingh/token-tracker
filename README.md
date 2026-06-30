# token-tracker

TokenCounter — track token burn and token costs for popular cloud LLM platforms
(Claude and OpenAI today; Gemini next). Native iOS **and** Android, bring-your-own-key,
privacy-first: your provider key stays on-device and is never sent anywhere except
that provider's API (`api.anthropic.com` or `api.openai.com`). No account, no server,
no analytics.

## Status

🚀 **Shipped and open source.** iOS is live on the App Store and Android is live on
Google Play. Both show month-to-date spend from Anthropic's Usage & Cost Admin API
(and now OpenAI's organization Costs API), with a per-model breakdown, a 30-day
trend, and a spend-limit gauge + 90% alert.

**Get it:**

- 📱 iOS — App Store: <https://apps.apple.com/app/id6772613833>
- 🤖 Android — Google Play: <https://play.google.com/store/apps/details?id=studio.maximumimpact.tokencounter>
- 🌐 Product page: <https://maximumimpact.studio/tokencounter/>

### Roadmap

- **Phase 1 (MVP):** ✅ iOS app, Claude platform only, month-to-date cost from the Anthropic Usage & Cost Admin API.
- **Phase 2:** ✅ Per-model breakdown, 30-day spend sparkline, and a spend-limit gauge with a 90%-of-limit alert.
- **Phase 3:** 🚧 OpenAI ✅ (organization Costs API live on both apps, see [ADR-014](docs/decisions.md)); Gemini next (see [api-research.md](docs/api-research.md)).
- **Phase 4:** ✅ Android app (native Kotlin + Jetpack Compose), at full feature parity with iOS.
- **Phase 5 (maybe):** Web app — undecided.

### Highlights so far

- **Two native apps, full parity.** SwiftUI on iOS, Jetpack Compose on Android — same dashboard, same features, same privacy posture.
- **Live data, on-device only.** Reads straight from the provider's cost API — Anthropic's Usage & Cost Admin API or OpenAI's organization Costs API — for finalized month-to-date spend (plus a token-priced estimate of today on Anthropic). Provider is auto-detected from the key prefix.
- **Spend limit + alert.** A local monthly target with a gauge (orange at 80%, red over 100%) and an opt-in once-a-month 90% notification. Console deep-links for the real billing limit/credit/auto-reload.
- **Open source.** Public repo, MIT-spirited — audit how your key is handled, file issues, send PRs.
- **Automated release pipelines.** CI ships signed builds to TestFlight (iOS) and Google Play internal testing (Android), with auto patch-version bumps.

## Repo layout

```
token-tracker/
├── README.md                # this file
├── docs/
│   ├── decisions.md         # ADR-style decision log
│   ├── api-research.md      # notes on each platform's billing API
│   └── architecture.md      # iOS app architecture
├── scripts/
│   └── cost_api_probe.py    # CLI to test/explore Anthropic cost API
├── ios/                     # Xcode project (iOS app source)
├── android/                 # Gradle / Jetpack Compose Android app source
├── backend/                 # (placeholder) any server-side helpers
└── .github/workflows/       # CI/CD pipelines
```

## Owner

- **Human:** Arun (arunjeetsingh@gmail.com)
- **Agent:** Chintu (this OpenClaw workspace)

## Quick links

- [Decision log](docs/decisions.md)
- [API research notes](docs/api-research.md)
- [Architecture](docs/architecture.md)
- Anthropic Usage & Cost API docs: <https://platform.claude.com/docs/en/manage-claude/usage-cost-api>

## How to run things

### Test the Anthropic cost API
```bash
python3 scripts/cost_api_probe.py --mtd
```
Reads admin key from `~/.openclaw/workspace/secrets/anthropic-admin-key.txt`.

### Android app

Native Kotlin + Jetpack Compose. Lives under `android/` and uses Gradle with the Kotlin DSL (KTS). See [ADR-013](docs/decisions.md) for the why.

Prereqs:

- **JDK 21** (Temurin or Homebrew's `openjdk@21`).
- **Android SDK** with platform `android-36` and build-tools `36.0.0`. Easiest path: install [Android Studio](https://developer.android.com/studio) and let it provision the SDK, or `brew install --cask android-commandlinetools` and run `sdkmanager "platforms;android-36" "build-tools;36.0.0" "platform-tools"`.
- Export `ANDROID_HOME` to your SDK root (e.g. `/opt/homebrew/share/android-commandlinetools` for the Homebrew cask).

Build a debug APK:

```bash
cd android
./gradlew assembleDebug
```

Run unit tests:

```bash
cd android
./gradlew test
```

Run on an emulator (after creating an AVD in Android Studio or via `avdmanager`):

```bash
# Start an emulator (replace Pixel_7_API_36 with your AVD name)
$ANDROID_HOME/emulator/emulator -avd Pixel_7_API_36 &

# Wait for it to come online, then install the debug APK
cd android
./gradlew installDebug
adb shell am start -n studio.maximumimpact.tokencounter/.MainActivity
```

The shipping build has a full live data layer: it reads the Anthropic Cost & Usage API, computes month-to-date spend plus a token-priced estimate of today, caches the last snapshot for instant cold launch, and stores the admin key in the Android Keystore. (A review/demo key short-circuits to a canned snapshot so store review never needs a real key.)

### iOS app

The `.xcodeproj` is **generated** from `ios/project.yml` via [XcodeGen](https://github.com/yonsm/XcodeGen) so it stays diff-friendly. First-time setup:

```bash
brew install xcodegen
cd ios
xcodegen generate
open TokenTracker.xcodeproj
```

Command-line build & test (CI does the same):

```bash
cd ios
xcodegen generate
xcodebuild \
  -project TokenTracker.xcodeproj \
  -scheme TokenTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  clean test
```

## Workflow

- **Public, open-source repo** on GitHub (`arunjeetsingh/token-tracker`).
- **PRs only.** The convention is enforced by a local pre-push hook. Install it after cloning:
  ```bash
  ./scripts/install-git-hooks.sh
  ```
  This blocks `git push origin main`. Override only in emergencies with `git push --no-verify origin main`.
- Arun reviews and merges every PR.
- CI runs on every PR via GitHub Actions (Python lint + iOS/Android build & test).
- **Release pipelines** (manual dispatch): `testflight.yml` builds + uploads the iOS app to TestFlight; `android-release.yml` builds a signed AAB and publishes to Google Play (internal track). Both auto-bump the patch version and commit it back to `main` with `[skip ci]`.
