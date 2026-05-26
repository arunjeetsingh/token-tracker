---
layout: default
title: Privacy Policy
permalink: /privacy/
---

# Token Counter — Privacy Policy

_Last updated: 2026-05-25_

Token Counter is a privacy-friendly iOS app that lets you monitor your Anthropic API spend without sharing your data with anyone but Anthropic.

## TL;DR

- **We don't have a server.** Token Counter has no backend. There is nowhere for us to collect your data even if we wanted to.
- **Your Anthropic Admin API key stays on your device**, stored in the iOS Keychain, protected by Face ID / Touch ID / your device passcode.
- **Your usage and cost data come from Anthropic**, fetched directly from your device. We never see it, store it, or proxy it.
- **No analytics, no crash reporting, no advertising SDKs, no third-party trackers.** None of it.
- **No account.** There is no Token Counter account to create.

## What Token Counter does

Token Counter is a viewer for your Anthropic API account's spend. When you launch the app:

1. You paste your Anthropic **Admin API key** once. The key is stored in the iOS Keychain on this device.
2. The app makes API requests directly from your iPhone to `api.anthropic.com` using your key, fetching cost and usage data for your organization.
3. The app displays month-to-date cost, today's intra-day estimate, and a breakdown by model.

That's the whole product. No upload, no relay, no third party.

## What data Token Counter handles

| Data | Where it comes from | Where it goes | Where it's stored |
| --- | --- | --- | --- |
| **Anthropic Admin API key** | You paste it from your clipboard | Only to Anthropic's API, as the `x-api-key` header | iOS Keychain on your device |
| **Cost & usage figures** | Anthropic's API | Displayed in the app | In-memory; not persisted across launches |
| **App preferences** (last-viewed model, etc.) | The app itself | Nowhere | iOS `UserDefaults` on your device |

We never receive any of this data. The app developer (Arunjeet Singh) has no visibility into your usage, cost, or key.

## What Token Counter does *not* do

- Token Counter does **not** include any analytics SDK (no Firebase, Amplitude, Mixpanel, Segment, etc.).
- Token Counter does **not** include any crash reporting SDK (no Crashlytics, Sentry, Bugsnag, etc.).
- Token Counter does **not** include any advertising SDK or ad network.
- Token Counter does **not** connect to any servers other than `api.anthropic.com`.
- Token Counter does **not** require an account, sign-in, or email address.
- Token Counter does **not** share data with any third party.

## Anthropic's role

When you use Token Counter, you are interacting with Anthropic's API. Anthropic operates `api.anthropic.com`, sees the requests your device makes, and applies their own privacy policy to that data:

> [https://www.anthropic.com/legal/privacy](https://www.anthropic.com/legal/privacy)

Token Counter does not modify or extend Anthropic's policy; we just visualize the cost/usage figures Anthropic returns.

## Children's privacy

Token Counter is not directed at children under 13. We do not knowingly collect any data from anyone (see above), including children.

## Security

- Your admin key is stored in the iOS Keychain with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. It does not back up to iCloud and does not migrate to a new device.
- The "Disconnect" option in Settings deletes the key from the Keychain. After that the app holds no credentials.
- All API requests are TLS-encrypted by iOS's URL loading system. ATS is enabled and not exempted.

## Changes to this policy

If we ever start collecting data (we don't plan to), this policy will be updated, and a clearly visible note will appear in the app's What's New on the App Store before the change goes live.

## Contact

Questions or concerns:

- File an issue: [github.com/arunjeetsingh/token-tracker/issues](https://github.com/arunjeetsingh/token-tracker/issues)
- Email: _(add a contact email here if you want one shown publicly)_
