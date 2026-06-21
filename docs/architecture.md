# iOS Architecture (MVP)

## Goals

- Single screen: shows MTD cost for the configured provider organization.
- Pull-to-refresh.
- Secure credential storage.
- Offline-friendly: shows last known value with a timestamp.

## Stack

- **SwiftUI** (iOS 17+)
- **Swift async/await** (no Combine, no RxSwift)
- **URLSession** for HTTP (no Alamofire)
- **Keychain Services** for the provider key
- **XCTest** for unit tests
- **swiftlint** for style

## Modules

```
TokenTracker.app
├── App/
│   └── TokenTrackerApp.swift       # @main, root view
├── Features/
│   └── Dashboard/
│       ├── DashboardView.swift     # the one screen
│       ├── DashboardViewModel.swift
│       └── DashboardState.swift    # idle | loading | loaded(amount, fetchedAt) | error
├── Providers/
│   ├── Anthropic/
│   │   ├── AnthropicClient.swift   # actor, org identity + MTD spend
│   │   └── AnthropicModels.swift   # Codable structs matching API JSON
│   └── OpenAI/
│       └── OpenAIClient.swift      # actor, organization costs API adapter
├── Credentials/
│   ├── KeychainStore.swift         # generic Keychain wrapper
│   └── CredentialPrompt.swift      # paste/edit UI for the admin key
├── Core/
│   ├── Money.swift                 # typed dollars wrapper, cents→USD conversion
│   ├── DateRange.swift             # MTD helpers
│   └── Logger.swift                # os.Logger thin wrapper
└── Tests/
    ├── AnthropicClientTests.swift
    └── MoneyTests.swift
```

## Data flow

1. App launches → reads provider key from Keychain (Face ID gated).
2. If key missing → show paste-in UI.
3. If key present → classify the provider by key prefix:
   - `sk-ant-...` → Anthropic Admin API.
   - anything else → OpenAI organization Costs API.
4. The live cost provider creates a short-lived client, fetches identity + month-to-date spend, normalizes to shared `MTDCost`, then renders.
5. On error, show the error + a retry button. Don't burn the key unless the provider reports 401/403.

## Security

- Provider key in Keychain with attributes:
  - `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
  - `kSecAttrSynchronizable = false`
- App requires Face ID / passcode every cold launch (LocalAuthentication).
- No logging of the key, ever. Use `os.Logger` with `.private` interpolation.
- TLS pinning is deferred; MVP uses default ATS for `api.anthropic.com` and `api.openai.com`.

## Testing strategy

- **Unit tests:** Money conversion, JSON decoding fixtures, pagination logic with mock URLSession/MockWebServer, provider routing, and auth-error normalization.
- **UI tests:** None for MVP — single screen, manually verified.
- **CI:** `xcodebuild -scheme TokenTracker test -destination 'platform=iOS Simulator,name=iPhone 15'`.

## Open questions

- Color theme: light/dark only, or do we want a fun gradient/glow when burn is high? 🔥
- Notifications: do we want push for "you crossed $X today"? Punted to Phase 2.
- Multi-workspace: org has multiple workspaces; do we show aggregate or per-workspace tabs? MVP = aggregate.
