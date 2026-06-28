import Foundation

/// Thin client for the subset of the Anthropic Usage & Cost Admin API
/// we need for the MVP. Single responsibility: month-to-date cost.
actor AnthropicClient {
    private let baseURL: URL
    private let apiVersion: String
    private let session: URLSession
    private let decoder: JSONDecoder
    private let apiKey: String

    init(
        apiKey: String,
        baseURL: URL = URL(string: "https://api.anthropic.com")!,  // swiftlint:disable:this force_unwrapping
        apiVersion: String = "2023-06-01",
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.apiVersion = apiVersion
        self.session = session
        self.decoder = Self.sharedDecoder
    }

    /// Shared across every client instance: the decoder and its date strategy
    /// are stateless once configured, so there's no reason to rebuild them per
    /// `init`. Callers that construct a client per request (e.g.
    /// `LiveCostProvider`) then pay only for the tiny actor wrapper. Mirrors the
    /// `JSONDecoder.snapshot` pattern in `DashboardCache`.
    private static let sharedDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        decoder.dateDecodingStrategy = .custom { dec in
            let container = try dec.singleValueContainer()
            let str = try container.decode(String.self)
            if let d = iso.date(from: str) { return d }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "unsupported ISO8601 timestamp: \(str)"
            )
        }
        return decoder
    }()

    /// GET /v1/organizations/me — quick auth sanity check.
    func whoami() async throws -> AnthropicAPI.OrgIdentity {
        let req = try request(path: "/v1/organizations/me", query: [:])
        let (data, _) = try await session.dataAndThrowOnHTTPError(req)
        return try decoder.decode(AnthropicAPI.OrgIdentity.self, from: data)
    }

    /// Combined month-to-date result: `cost_report` for finalized days +
    /// `usage_report/messages` × pricing table for today's partial day.
    ///
    /// Why this exists: Anthropic's `cost_report` endpoint emits one bucket
    /// per *closed* UTC day. Today's spend doesn't show up there until
    /// 00:00 UTC tomorrow. The Console shows today live; if we want to
    /// match the Console we have to estimate today ourselves from token
    /// usage × public pricing.
    func monthToDateCost(now: Date = Date()) async throws -> MTDCost {
        let startOfMonth = Self.startOfMonth(utc: now)
        let startOfTodayUTC = Self.startOfDay(utc: now)
        // Sparkline window: prefer the trailing 30 days of finalized data
        // (start-of-day 30d ago, UTC). When the user is early in the month
        // that means we'll pull a few days from the previous month — which
        // is exactly what we want for the dashboard sparkline ("last 30
        // days of spend") even though the hero number remains MTD only.
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = TimeZone(identifier: "UTC")! // swiftlint:disable:this force_unwrapping
        let sparklineStart = cal.date(byAdding: .day, value: -30, to: startOfTodayUTC) ?? startOfMonth

        // Per-day + per-model breakdown for the sparkline range. Sparkline
        // and model breakdown both come from this single response — one
        // network round-trip, one source of truth. The MTD finalized total
        // is also derived from this, restricted to the in-month subset.
        let detail: CostDetail
        if startOfTodayUTC > sparklineStart {
            detail = try await costDetail(start: sparklineStart, end: startOfTodayUTC)
        } else {
            detail = CostDetail(daily: [], perModel: [:])
        }
        // Hero MTD finalized = sum of daily buckets that fall within this
        // calendar month (cost_report buckets are UTC-day-aligned).
        var finalized = Money.zero
        for d in detail.daily where d.date >= startOfMonth {
            finalized += d.cost
        }
        // Model breakdown: also restrict to in-month for hero consistency.
        var monthModels: [String: Money] = [:]
        for (key, perDay) in detail.perModel {
            var total = Money.zero
            for d in perDay where d.date >= startOfMonth {
                total += d.cost
            }
            if total.cents > 0 {
                monthModels[key] = total
            }
        }
        let modelBreakdown = monthModels
            .map { ModelSpend(modelId: $0.key, displayName: Self.displayName(forModelId: $0.key), cost: $0.value) }
            .sorted { $0.cost.cents > $1.cost.cents }

        // Today's intra-day estimate (may include unpriced models).
        let today = try await todayEstimatedCost(now: now)

        return MTDCost(
            finalizedCost: finalized,
            todayEstimatedCost: today.cost,
            unpricedModels: today.unpricedModels,
            finalizedThrough: startOfTodayUTC,
            asOf: now,
            dailySpend: detail.daily,
            modelBreakdown: modelBreakdown
        )
    }

    /// Sums every row across paginated cost_report results.
    func totalCost(start: Date, end: Date) async throws -> Money {
        let detail = try await costDetail(start: start, end: end)
        var total = Money.zero
        for d in detail.daily {
            total += d.cost
        }
        return total
    }

    /// Aggregated cost_report result: one entry per UTC day, and a
    /// per-(model, day) breakdown. Both come from the same paginated
    /// `/v1/organizations/cost_report` response grouped by description.
    /// (We can't ask for `group_by[]=model` directly — that endpoint only
    /// accepts `workspace_id` or `description`. Grouping by description
    /// returns one row per (model, token_type, cost_type, …) tuple per
    /// day; we then fold them on the client.)
    struct CostDetail: Equatable {
        let daily: [DailySpend]
        /// modelId -> per-day costs (sorted by date asc).
        let perModel: [String: [DailySpend]]
    }

    /// Pulls `cost_report` for the given window, grouped by description,
    /// and aggregates the response into a (daily total, per-model daily)
    /// projection. One network sweep, two views of the same data.
    ///
    /// Anthropic's `cost_report` rejects `group_by[]=model` with HTTP 400
    /// ("Valid options are \"description\", \"workspace_id\""). Grouping
    /// by description gives us the per-model split for free because each
    /// description-bucketed row carries its `model` field — except for
    /// non-token cost rows like `web_search` / `code_execution` which have
    /// `model: null`. Those still contribute to the daily total but get
    /// dropped from the per-model breakdown (no single model to attribute).
    func costDetail(start: Date, end: Date) async throws -> CostDetail {
        let isoOut = ISO8601DateFormatter()
        isoOut.formatOptions = [.withInternetDateTime]
        var query: [(String, String)] = [
            ("starting_at", isoOut.string(from: start)),
            ("ending_at", isoOut.string(from: end)),
            // 24h buckets give us one row per UTC day — exactly what the
            // sparkline wants. (Default bucket_width is already daily, but
            // we set it explicitly so we don't drift if Anthropic flips the
            // default later.)
            ("bucket_width", "1d"),
            // `cost_report` only accepts `description` or `workspace_id`
            // for group_by[]. Description gives us per-(model, token_type,
            // cost_type, …) granularity, which we re-aggregate below.
            ("group_by[]", "description")
        ]
        var dailyTotals: [Date: Money] = [:]
        var perModel: [String: [Date: Money]] = [:]
        var pageGuard = 0
        while true {
            pageGuard += 1
            precondition(pageGuard < 200, "cost_report pagination guard tripped")
            let req = try request(path: "/v1/organizations/cost_report", queryPairs: query)
            let (data, _) = try await session.dataAndThrowOnHTTPError(req)
            let page = try decoder.decode(AnthropicAPI.CostReportPage.self, from: data)
            for bucket in page.data {
                let day = bucket.startingAt
                for row in bucket.results {
                    guard let money = Money.fromAnthropicCentsString(row.amount) else { continue }
                    dailyTotals[day, default: .zero] += money
                    if let model = row.model, !model.isEmpty {
                        var perDay = perModel[model] ?? [:]
                        perDay[day, default: .zero] += money
                        perModel[model] = perDay
                    }
                }
            }
            guard page.hasMore, let next = page.nextPage else { break }
            query = query.filter { $0.0 != "page" }
            query.append(("page", next))
        }
        let daily = dailyTotals
            .map { DailySpend(date: $0.key, cost: $0.value) }
            .sorted { $0.date < $1.date }
        let perModelArr = perModel.mapValues { dict in
            dict
                .map { DailySpend(date: $0.key, cost: $0.value) }
                .sorted { $0.date < $1.date }
        }
        return CostDetail(daily: daily, perModel: perModelArr)
    }

    /// Best-effort pretty name for Anthropic model ids that appear in the
    /// cost_report (e.g. `claude-opus-4-7` -> `Claude Opus 4.7`). When the
    /// id doesn't match a known pattern we fall back to the raw id so the
    /// UI never silently drops a row.
    static func displayName(forModelId id: String) -> String {
        let lower = id.lowercased()
        // Patterns: claude-<family>-<major>-<minor>[-suffix]
        struct Family { let key: String; let label: String }
        let families: [Family] = [
            .init(key: "opus",   label: "Claude Opus"),
            .init(key: "sonnet", label: "Claude Sonnet"),
            .init(key: "haiku",  label: "Claude Haiku")
        ]
        for fam in families {
            // claude-<fam>-X-Y...
            let prefix = "claude-\(fam.key)-"
            if lower.hasPrefix(prefix) {
                let rest = lower.dropFirst(prefix.count)
                let parts = rest.split(separator: "-").prefix(2).map(String.init)
                if parts.count == 2, Int(parts[0]) != nil, Int(parts[1]) != nil {
                    return "\(fam.label) \(parts[0]).\(parts[1])"
                }
                if parts.count >= 1, Int(parts[0]) != nil {
                    return "\(fam.label) \(parts[0])"
                }
            }
            // claude-3-5-sonnet etc.
            if lower.contains("-\(fam.key)") {
                // Strip leading "claude-" then find the major.minor before family.
                let stripped = lower.hasPrefix("claude-") ? String(lower.dropFirst("claude-".count)) : lower
                let segs = stripped.split(separator: "-").map(String.init)
                if let famIdx = segs.firstIndex(of: fam.key), famIdx >= 2,
                   Int(segs[famIdx - 2]) != nil, Int(segs[famIdx - 1]) != nil {
                    return "\(fam.label) \(segs[famIdx - 2]).\(segs[famIdx - 1])"
                }
                if let famIdx = segs.firstIndex(of: fam.key), famIdx >= 1,
                   Int(segs[famIdx - 1]) != nil {
                    return "\(fam.label) \(segs[famIdx - 1])"
                }
            }
        }
        return id
    }

    // MARK: - private

    private func request(path: String, query: [String: String]) throws -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = query.isEmpty ? nil : query.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components.url else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "accept")
        return req
    }

    /// Variant that supports repeated keys (e.g. `group_by[]`) which the
    /// `[String: String]` form can't express.
    fileprivate func request(path: String, queryPairs: [(String, String)]) throws -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = queryPairs.isEmpty ? nil : queryPairs.map { URLQueryItem(name: $0.0, value: $0.1) }
        guard let url = components.url else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "accept")
        return req
    }
}

// MARK: - Intra-day usage estimation

extension AnthropicClient {
    /// Returned by `todayEstimatedCost(now:)`.
    struct TodayEstimate {
        let cost: Money
        /// Model ids that appeared in usage but had no entry in `ModelPricing`.
        /// Surfaced so the UI can warn the user the estimate is incomplete.
        let unpricedModels: [String]
    }

    /// Estimates today's cost by pulling `usage_report/messages` at hourly
    /// granularity grouped by model, then multiplying by the local pricing
    /// table. Models we don't have pricing for are reported back so the
    /// caller can flag the estimate as incomplete.
    func todayEstimatedCost(now: Date = Date()) async throws -> TodayEstimate {
        let startOfToday = Self.startOfDay(utc: now)
        var query: [(String, String)] = [
            ("starting_at", Self.iso8601(startOfToday)),
            ("bucket_width", "1h"),
            ("group_by[]", "model"),
            ("limit", "48")
        ]

        // Accumulate token usage per model across all pages.
        var perModel: [String: TokenUsage] = [:]
        var pageGuard = 0
        while true {
            pageGuard += 1
            precondition(pageGuard < 50, "usage_report pagination guard tripped")
            let req = try request(path: "/v1/organizations/usage_report/messages", queryPairs: query)
            let (data, _) = try await session.dataAndThrowOnHTTPError(req)
            let page = try decoder.decode(AnthropicAPI.MessagesUsagePage.self, from: data)
            for bucket in page.data {
                for row in bucket.results {
                    let key = row.model ?? ""
                    let inc = TokenUsage(
                        uncachedInputTokens: row.uncachedInputTokens,
                        cacheWrite5mTokens: row.cacheCreation.ephemeral5mInputTokens,
                        cacheWrite1hTokens: row.cacheCreation.ephemeral1hInputTokens,
                        cacheReadTokens: row.cacheReadInputTokens,
                        outputTokens: row.outputTokens
                    )
                    perModel[key, default: .zero] = (perModel[key] ?? .zero) + inc
                }
            }
            guard page.hasMore, let next = page.nextPage else { break }
            // Preserve all base params; just swap/append the page token.
            query = query.filter { $0.0 != "page" }
            query.append(("page", next))
        }

        var totalDollars = Decimal(0)
        var unpriced: [String] = []
        for (model, usage) in perModel {
            guard let pricing = ModelPricing.lookup(model) else {
                if !model.isEmpty { unpriced.append(model) }
                continue
            }
            totalDollars += usage.cost(at: pricing)
        }

        return TodayEstimate(
            cost: Money.fromDollars(totalDollars),
            unpricedModels: unpriced.sorted()
        )
    }

    // MARK: - Time helpers (all UTC; cost_report buckets are UTC-anchored)

    static func startOfMonth(utc date: Date) -> Date {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = TimeZone(identifier: "UTC")! // swiftlint:disable:this force_unwrapping
        var comps = cal.dateComponents([.year, .month], from: date)
        comps.day = 1
        return cal.date(from: comps)! // swiftlint:disable:this force_unwrapping
    }

    static func startOfDay(utc date: Date) -> Date {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = TimeZone(identifier: "UTC")! // swiftlint:disable:this force_unwrapping
        return cal.startOfDay(for: date)
    }

    static func iso8601(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: date)
    }
}

/// One UTC-day bucket of finalized spend. Used by the dashboard sparkline.
/// `date` is the start of the day (UTC), `cost` is the finalized total for
/// that day across all models. Today is intentionally excluded — see
/// `MTDCost.dailySpend` for why.
struct DailySpend: Equatable, Hashable, Codable {
    let date: Date
    let cost: Money
}

/// One model's contribution to the month-to-date spend. Sorted descending
/// by `cost` by `AnthropicClient`. UI picks top N for display.
struct ModelSpend: Equatable, Hashable, Codable {
    /// Raw Anthropic model id (e.g. `claude-opus-4-7`).
    let modelId: String
    /// Pretty name (e.g. `Claude Opus 4.7`). May fall back to `modelId`
    /// when we can't parse the family/version.
    let displayName: String
    let cost: Money
}

/// Composite month-to-date number returned to the UI. `total` is what we
/// display front-and-center; the other fields exist so the UI can disclose
/// the gap honestly ("$607.12 · including ~$19.81 estimate for today").
struct MTDCost: Equatable, Codable {
    let finalizedCost: Money
    let todayEstimatedCost: Money
    /// Models that appeared in today's usage but had no pricing entry.
    /// Non-empty means the estimate is a lower bound.
    let unpricedModels: [String]
    /// UTC timestamp that splits finalized days from today's estimate
    /// (i.e. start-of-today-UTC).
    let finalizedThrough: Date
    /// When the report was generated.
    let asOf: Date
    /// Last ~30 days of finalized daily spend (sorted chronologically).
    /// Today is *not* included — it lives in `todayEstimatedCost` and
    /// would otherwise swing the last point wildly during the day.
    let dailySpend: [DailySpend]
    /// Per-model contribution to the MTD finalized cost, sorted descending.
    /// The dashboard renders the top 3.
    let modelBreakdown: [ModelSpend]

    init(
        finalizedCost: Money,
        todayEstimatedCost: Money,
        unpricedModels: [String],
        finalizedThrough: Date,
        asOf: Date,
        dailySpend: [DailySpend] = [],
        modelBreakdown: [ModelSpend] = []
    ) {
        self.finalizedCost = finalizedCost
        self.todayEstimatedCost = todayEstimatedCost
        self.unpricedModels = unpricedModels
        self.finalizedThrough = finalizedThrough
        self.asOf = asOf
        self.dailySpend = dailySpend
        self.modelBreakdown = modelBreakdown
    }

    var total: Money { finalizedCost + todayEstimatedCost }
    var hasTodayEstimate: Bool { todayEstimatedCost.cents > 0 }
    var hasUnpricedModels: Bool { !unpricedModels.isEmpty }
}

func combineMTDCosts(_ reports: [MTDCost]) -> MTDCost {
    precondition(!reports.isEmpty, "At least one report is required")
    let daily = Dictionary(grouping: reports.flatMap { $0.dailySpend }, by: { $0.date })
        .map { date, rows in DailySpend(date: date, cost: Money(cents: rows.reduce(Int64(0)) { $0 + $1.cost.cents })) }
        .sorted { $0.date < $1.date }
    let models = Dictionary(grouping: reports.flatMap { $0.modelBreakdown }, by: { $0.modelId + "\u{1f}" + $0.displayName })
        .map { _, rows in
            let first = rows[0]
            return ModelSpend(modelId: first.modelId, displayName: first.displayName, cost: Money(cents: rows.reduce(Int64(0)) { $0 + $1.cost.cents }))
        }
        .sorted { $0.cost.cents > $1.cost.cents }
    return MTDCost(
        finalizedCost: Money(cents: reports.reduce(Int64(0)) { $0 + $1.finalizedCost.cents }),
        todayEstimatedCost: Money(cents: reports.reduce(Int64(0)) { $0 + $1.todayEstimatedCost.cents }),
        unpricedModels: Array(Set(reports.flatMap { $0.unpricedModels })).sorted(),
        finalizedThrough: reports.map { $0.finalizedThrough }.min() ?? Date(),
        asOf: reports.map { $0.asOf }.max() ?? Date(),
        dailySpend: daily,
        modelBreakdown: models
    )
}

extension URLSession {
    /// Convenience: throws on non-2xx responses; otherwise returns body + response.
    func dataAndThrowOnHTTPError(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, resp) = try await data(for: request)
        guard let http = resp as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw AnthropicHTTPError(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
        return (data, http)
    }
}

struct AnthropicHTTPError: LocalizedError {
    let status: Int
    let body: String
    var errorDescription: String? { "HTTP \(status): \(body.prefix(200))" }
}
