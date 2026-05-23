# TestFlight + Fastlane setup

One-time configuration so CI can push builds to TestFlight automatically.

## Big picture

1. Create an **App Store Connect API key** (preferred over Apple-ID + 2FA — no password handling, no expiring sessions).
2. Create the app record in App Store Connect (one-time).
3. Add the API key + a couple of small constants as **GitHub Actions secrets/vars** on the repo.
4. Trigger the **TestFlight beta** workflow manually the first time. After that, every successful manual dispatch (or eventual auto-trigger) uploads a new build to TestFlight internal testers.
5. Install the **TestFlight app** on your iPhone, sign in with your Apple ID, and the new build will show up automatically.

---

## 1. App Store Connect API key

1. Sign in at <https://appstoreconnect.apple.com/access/api>.
2. Click **+ Generate API Key**.
3. Name: `token-tracker CI`.
4. Access: **App Manager** (Admin works too; App Manager is the least privilege that supports TestFlight uploads).
5. Download the `.p8` file Apple gives you. You only get to download it once.
6. Note the **Key ID** (10 chars) and the **Issuer ID** (UUID at the top of the page).

## 2. App record in App Store Connect

1. Go to <https://appstoreconnect.apple.com/apps>.
2. Click **+ → New App**.
3. Platform: iOS. Name: **Token Tracker** (or whatever).
4. Primary language: English (US).
5. Bundle ID: select `ai.openclaw.tokentracker.TokenTracker`. (If it isn't in the dropdown, register it first under <https://developer.apple.com/account/resources/identifiers/list>.)
6. SKU: `tokentracker` (any unique string).
7. User access: Full Access.

That's enough for TestFlight. App Store metadata can wait until you're ready to ship publicly.

## 3. GitHub Actions configuration

In <https://github.com/arunjeetsingh/token-tracker/settings/secrets/actions>, create an **Environment** named `testflight` first (Settings → Environments → New environment). Put the secrets in that environment for a small layer of protection (manual approval before the workflow can use them, if you want).

### Repository variables (plain values, not secret)

| Name | Value |
| --- | --- |
| `APP_IDENTIFIER` | `ai.openclaw.tokentracker.TokenTracker` |
| `APPLE_TEAM_ID` | Your 10-character team ID (developer.apple.com → Membership) |

### Environment secrets (`testflight` env)

| Name | Value |
| --- | --- |
| `APP_STORE_CONNECT_API_KEY_ID` | The 10-char Key ID from step 1 |
| `APP_STORE_CONNECT_API_ISSUER_ID` | The UUID Issuer ID from step 1 |
| `APP_STORE_CONNECT_API_KEY_B64` | `base64 -i AuthKey_XXXXXXX.p8 | pbcopy` then paste |

## 4. Trigger the workflow

1. Repo → **Actions** tab → **TestFlight beta** workflow → **Run workflow**.
2. Optionally fill in release notes.
3. Wait ~10-15 min for the build + upload.
4. App Store Connect → your app → TestFlight tab → build will appear in "Processing", then "Ready to Test" once Apple finishes processing (~5-15 min after upload).
5. Add yourself as an **Internal Tester** (TestFlight tab → Internal Testing group → add by Apple ID). Internal testers don't need Beta Review.

## 5. TestFlight on your phone

1. Install **TestFlight** from the App Store on your iPhone.
2. Sign in with the same Apple ID.
3. New builds appear automatically; tap to install/update.

## Local dev (not TestFlight)

For day-to-day dev iteration, you still build locally and run on a connected iPhone via Xcode (paid team, automatic signing). TestFlight is for "I want to test the actual release build on my phone without plugging into the mini" or for sharing with other testers.

Local once-only:

```bash
cd ios
xcodegen generate
open TokenTracker.xcodeproj
# Signing & Capabilities → Team = your paid team
# Plug iPhone in, ⌘R
```

## Verifying the Fastfile locally

```bash
cd ios
brew install fastlane    # if not already installed
# Lint the Fastfile syntax without uploading:
fastlane lanes
fastlane bump_build      # safe; only edits project.yml's build number locally
```

`fastlane beta` will fail locally without all four env vars set — that's expected. The CI workflow provides them.
