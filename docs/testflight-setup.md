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
| `APP_STORE_CONNECT_API_KEY_B64` | `base64 -i AuthKey_XXXXXXX.p8 \| pbcopy` then paste |
| `MATCH_PASSWORD` | Encryption password for the cert storage repo (see *Cert storage with `match`* below) |
| `MATCH_DEPLOY_KEY` | Full contents of the SSH private key (`secrets/match/deploy_key`) for the cert storage repo |

## 3a. Cert storage with `fastlane match`

Apple caps Distribution certificates at **3 per account**. The first iteration of this CI burned through that quota in two runs because each ephemeral CI keychain didn't have the existing cert's private key and asked Apple for a new one. `fastlane match` solves this by keeping a single cert + provisioning profile encrypted in a private git repo that CI clones on every run.

**One-time setup (already done for this repo):**

1. **Storage repo:** <https://github.com/arunjeetsingh/token-tracker-certs> — private, empty on first run; `match` populates it on the first successful CI invocation.
2. **Read/write deploy key:** Generated locally, public half attached to `token-tracker-certs` via `gh repo deploy-key add`, private half stored as the `MATCH_DEPLOY_KEY` env secret on the `testflight` environment.
3. **Encryption password:** Generated locally (32 random base64 chars), stored at `~/.openclaw/workspace/secrets/match/MATCH_PASSWORD` and copied into the `MATCH_PASSWORD` env secret.
4. **Matchfile:** `ios/fastlane/Matchfile` points at the storage repo over SSH. Same config works locally (uses your normal GitHub SSH) and in CI (uses the deploy key via `ssh-agent`).

**First CI run after the match migration:**
- `match(type: "appstore", readonly: false)` finds the storage repo empty, calls ASC API to create a single new Apple Distribution cert + AppStore provisioning profile, encrypts them with `MATCH_PASSWORD`, and pushes them to `token-tracker-certs`.

**Every subsequent CI run:**
- `match` clones the storage repo, decrypts the existing cert + profile into the ephemeral CI keychain, and signs the build. **No new cert is created.** If Apple ever shows more than 1 Distribution cert in <https://developer.apple.com/account/resources/certificates/list>, something is misconfigured — see *Recovering from a cert quota error* below.

**Local dev:**
- `cd ios && fastlane match appstore --readonly` will fetch the same cert into your local keychain (assuming your GitHub SSH access can reach `token-tracker-certs`). You generally don't need this unless you're producing TestFlight-grade builds locally; Xcode's automatic signing with your paid team is fine for run-on-device.

**Recovering from a cert quota error:**
1. Revoke any extra certs at <https://developer.apple.com/account/resources/certificates/list> until 0 remain.
2. Empty the storage repo: `cd ~/somewhere/token-tracker-certs && rm -rf certs profiles && git commit -am 'reset' && git push`.
3. Re-run the TestFlight workflow. `match` will bootstrap a fresh cert and push it back to storage.

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
