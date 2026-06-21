# Provider Billing API Research

## Anthropic — Usage & Cost Admin API ✅ working

- **Docs:** <https://platform.claude.com/docs/en/manage-claude/usage-cost-api>
- **Base URL:** `https://api.anthropic.com`
- **Auth:** `x-api-key: <admin-key>` + `anthropic-version: 2023-06-01`
- **Requires:** Admin API key (org accounts only).

### Validated endpoints

#### `GET /v1/organizations/me`
Identity check. Returns `{ id, type, name }`. Arun's org: `Maximum Impact` (`402418a7-…`).

#### `GET /v1/organizations/cost_report`
Returns per-day cost buckets within the requested range.

**Query params (validated):**
- `starting_at` (required) — ISO-8601 UTC timestamp, inclusive.
- `ending_at` (required) — ISO-8601 UTC timestamp, exclusive.
- `page` — opaque pagination cursor from `next_page`.

**Response shape:**
```json
{
  "data": [
    {
      "starting_at": "2026-05-01T00:00:00Z",
      "ending_at":   "2026-05-02T00:00:00Z",
      "results": [
        {
          "currency": "USD",
          "amount": "2013.9595",         // ⚠️ CENTS, not dollars
          "workspace_id": null,
          "description": null,
          "cost_type": null,
          "context_window": null,
          "model": null,
          "service_tier": null,
          "token_type": null,
          "inference_geo": null
        }
      ]
    },
    ...
  ],
  "has_more": true,
  "next_page": "page_<base64>"
}
```

**⚠️ Critical gotcha:** `amount` is in **cents USD**, despite `currency: "USD"`. Divide by 100 for dollars. See ADR-005.

**Pagination:** Empirically, ~7 days per page. May-2026 MTD (23 days) returned 4 pages.

#### `GET /v1/organizations/usage_report/messages` — TODO
Per-day token counts (input/output/cache, by model). Will explore once we want per-model breakdown.

### Sanity check vs dashboard

| Date          | API total (cents) | API total (USD) | Dashboard |
|---------------|------------------:|----------------:|----------:|
| 2026-05-01..23| 56,073.4392       | $560.73         | $562.03   |

Diff $1.30 — within expected: real-time dashboard vs snapshot + UTC vs PT day boundary.

### Plan for iOS

1. `AnthropicClient` actor with single method: `mtdCostUSD() async throws -> Decimal`.
2. Internally paginates, sums `amount`, divides by 100, returns Decimal.
3. Unit test: feed a fixture JSON, assert correct dollar conversion.
4. Cache last value + fetch time for offline display.

---

## OpenAI — Organization Costs API ✅ implemented

- **Base URL:** `https://api.openai.com`
- **Auth:** standard HTTP Authorization bearer-token header
- **Endpoint:** `GET /v1/organization/costs`
- **Requires:** An OpenAI key with access to organization cost data.

### Implemented endpoint

#### `GET /v1/organization/costs`
Returns cost buckets for an organization in epoch-second windows.

**Query params used by the apps:**
- `start_time` — UTC epoch seconds, inclusive.
- `end_time` — UTC epoch seconds, exclusive.
- `bucket_width=1d` — daily buckets for the dashboard sparkline.
- `group_by[]=line_item` — line-item/model-ish breakdown rows.
- `limit=30` — page size.
- `page` — opaque pagination cursor from `next_page`.

**Response shape consumed:**
```json
{
  "data": [
    {
      "start_time": 1764547200,
      "end_time": 1764633600,
      "results": [
        {
          "amount": { "value": "12.34", "currency": "usd" },
          "line_item": "model:gpt-4o-mini",
          "project_id": null
        }
      ]
    }
  ],
  "has_more": true,
  "next_page": "page_cursor"
}
```

**Money semantics:** OpenAI `amount.value` is treated as decimal USD. This differs from Anthropic's cost report, where `amount` is cents and must be divided by 100.

**Identity check:** OpenAI does not expose a cheap org-name endpoint for this app's current scope. `whoami` probes a one-day costs window with `limit=1`; a successful response returns a generic `OpenAI Organization` identity, while HTTP 401/403 is normalized as an auth error.

**Docs note:** Direct fetches of OpenAI platform docs from the local validation environment returned HTTP 403, so the contract is locked by Android MockWebServer tests and iOS URLProtocol tests rather than by checked-in live examples.

---

## Google Gemini — TODO (Phase 3)

Brief: Cloud Billing API in GCP; integrates via service account. Plan to investigate in Phase 3.
