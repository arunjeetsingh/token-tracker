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
TBD — pending Xcode install + first project commit.

## Workflow

- **Private repo** on GitHub (`arunjeetsingh/token-tracker`).
- **PRs only** after first push — `main` is protected.
- Arun reviews and merges every PR.
- CI runs on every PR via GitHub Actions (lint + test).
