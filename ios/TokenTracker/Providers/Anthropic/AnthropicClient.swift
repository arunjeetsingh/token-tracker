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
        self.decoder = decoder
    }

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

        // Finalized cost: closed UTC days only.
        let finalized: Money
        if startOfTodayUTC > startOfMonth {
            finalized = try await totalCost(start: startOfMonth, end: startOfTodayUTC)
        } else {
            // First of the month, UTC — no closed days yet.
            finalized = .zero
        }

        // Today's intra-day estimate (may include unpriced models).
        let today = try await todayEstimatedCost(now: now)

        return MTDCost(
            finalizedCost: finalized,
            todayEstimatedCost: today.cost,
            unpricedModels: today.unpricedModels,
            finalizedThrough: startOfTodayUTC,
            asOf: now
        )
    }

    /// Sums every row across paginated cost_report results.
    func totalCost(start: Date, end: Date) async throws -> Money {
        let isoOut = ISO8601DateFormatter()
        isoOut.formatOptions = [.withInternetDateTime]
        var query: [String: String] = [
            "starting_at": isoOut.string(from: start),
            "ending_at": isoOut.string(from: end)
        ]

        var total = Money.zero
        var pageGuard = 0
        while true {
            pageGuard += 1
            precondition(pageGuard < 200, "cost_report pagination guard tripped")
            let req = try request(path: "/v1/organizations/cost_report", query: query)
            let (data, _) = try await session.dataAndThrowOnHTTPError(req)
            let page = try decoder.decode(AnthropicAPI.CostReportPage.self, from: data)
            for bucket in page.data {
                for row in bucket.results {
                    if let money = Money.fromAnthropicCentsString(row.amount) {
                        total += money
                    }
                }
            }
            guard page.hasMore, let next = page.nextPage else { break }
            query["page"] = next
        }
        return total
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

/// Composite month-to-date number returned to the UI. `total` is what we
/// display front-and-center; the other fields exist so the UI can disclose
/// the gap honestly ("$607.12 · including ~$19.81 estimate for today").
struct MTDCost: Equatable {
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

    var total: Money { finalizedCost + todayEstimatedCost }
    var hasTodayEstimate: Bool { todayEstimatedCost.cents > 0 }
    var hasUnpricedModels: Bool { !unpricedModels.isEmpty }
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
