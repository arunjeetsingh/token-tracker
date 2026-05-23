# iOS Architecture (MVP)

## Goals

- Single screen: shows MTD cost for the configured Anthropic org.
- Pull-to-refresh.
- Secure credential storage.
- Offline-friendly: shows last known value with a timestamp.

## Stack

- **SwiftUI** (iOS 17+)
- **Swift async/await** (no Combine, no RxSwift)
- **URLSession** for HTTP (no Alamofire)
- **Keychain Services** for the admin key
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
│   └── Anthropic/
│       ├── AnthropicClient.swift   # actor, single method mtdCostUSD()
│       ├── AnthropicModels.swift   # Codable structs matching API JSON
│       └── AnthropicEndpoints.swift
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

1. App launches → reads admin key from Keychain (Face ID gated).
2. If key missing → show paste-in UI.
3. If key present → `AnthropicClient.mtdCostUSD()` → render.
4. On error, show the error + a retry button. Don't burn the key.

## Security

- Admin key in Keychain with attributes:
  - `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
  - `kSecAttrSynchronizable = false`
- App requires Face ID / passcode every cold launch (LocalAuthentication).
- No logging of the key, ever. Use `os.Logger` with `.private` interpolation.
- TLS pinned to `api.anthropic.com` cert (Phase 2; MVP uses default ATS).

## Testing strategy

- **Unit tests:** Money conversion, JSON decoding fixtures, pagination logic with mock URLSession.
- **UI tests:** None for MVP — single screen, manually verified.
- **CI:** `xcodebuild -scheme TokenTracker test -destination 'platform=iOS Simulator,name=iPhone 15'`.

## Open questions

- Color theme: light/dark only, or do we want a fun gradient/glow when burn is high? 🔥
- Notifications: do we want push for "you crossed $X today"? Punted to Phase 2.
- Multi-workspace: org has multiple workspaces; do we show aggregate or per-workspace tabs? MVP = aggregate.
