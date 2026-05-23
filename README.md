# token-tracker

Track token burn and token costs for popular cloud LLM platforms (Claude, OpenAI, Gemini, …) — iOS first.

## Status

🚧 MVP in progress.

- **Phase 1 (MVP):** iOS app, Claude platform only, shows month-to-date cost from the Anthropic Usage & Cost Admin API.
- **Phase 2:** Add per-model breakdowns, daily/weekly trends, alerts.
- **Phase 3:** OpenAI + Gemini support.
- **Phase 4:** Android.
- **Phase 5 (maybe):** Web app.

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

- **Private repo** on GitHub (`arunjeetsingh/token-tracker`).
- **PRs only** after first push. Branch protection isn't configurable on free-tier private repos, so the convention is enforced by a local pre-push hook. Install it after cloning:
  ```bash
  ./scripts/install-git-hooks.sh
  ```
  This blocks `git push origin main`. Override only in emergencies with `git push --no-verify origin main`.
- Arun reviews and merges every PR.
- CI runs on every PR via GitHub Actions (Python lint + iOS build/test).
