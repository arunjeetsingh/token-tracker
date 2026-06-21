import Foundation

/// Wire types for OpenAI's organization Costs API.
enum OpenAIAPI {
    struct CostPage: Decodable {
        let data: [CostBucket]
        let hasMore: Bool
        let nextPage: String?

        enum CodingKeys: String, CodingKey {
            case data
            case hasMore = "has_more"
            case nextPage = "next_page"
        }
    }

    struct CostBucket: Decodable {
        let startTime: Int64
        let endTime: Int64?
        let results: [CostResult]

        enum CodingKeys: String, CodingKey {
            case startTime = "start_time"
            case endTime = "end_time"
            case results
        }
    }

    struct CostResult: Decodable {
        let amount: Amount
        let lineItem: String?
        let projectId: String?

        enum CodingKeys: String, CodingKey {
            case amount
            case lineItem = "line_item"
            case projectId = "project_id"
        }
    }

    struct Amount: Decodable {
        /// Decimal USD value for this cost bucket.
        let value: String
        let currency: String?
    }
}

/// Thin client for OpenAI's organization Costs API.
///
/// OpenAI's costs endpoint returns daily buckets in epoch seconds and amount
/// values in USD. Unlike Anthropic, OpenAI already includes today's bucket in
/// the costs feed, so we expose the returned month-to-date total directly and
/// keep `todayEstimatedCost` at zero.
actor OpenAIClient {
    private let apiKey: String
    private let baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder

    init(
        apiKey: String,
        baseURL: URL = URL(string: "https://api.openai.com")!, // swiftlint:disable:this force_unwrapping
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.session = session
        self.decoder = JSONDecoder()
    }

    /// Quick auth sanity check. OpenAI does not expose a cheap org-name endpoint
    /// for this scope; a one-day costs probe verifies bearer-token access.
    func whoami(now: Date = Date()) async throws -> AnthropicAPI.OrgIdentity {
        let today = Self.startOfDay(utc: now)
        _ = try await costs(start: today, end: Self.addDays(1, to: today), limit: 1)
        return AnthropicAPI.OrgIdentity(id: "openai", type: "organization", name: "OpenAI Organization")
    }

    func monthToDateCost(now: Date = Date()) async throws -> MTDCost {
        let today = Self.startOfDay(utc: now)
        let startOfMonth = Self.startOfMonth(utc: now)
        let sparklineStart = Self.addDays(-30, to: today)
        let start = min(startOfMonth, sparklineStart)
        let endExclusive = Self.addDays(1, to: today)

        var dailyTotals: [Date: Money] = [:]
        var perLineItem: [String: [Date: Money]] = [:]
        var page: String?
        var pageGuard = 0

        while true {
            pageGuard += 1
            precondition(pageGuard < 200, "OpenAI costs pagination guard tripped")
            let response = try await costs(start: start, end: endExclusive, page: page)
            for bucket in response.data {
                let day = Date(timeIntervalSince1970: TimeInterval(bucket.startTime))
                for row in bucket.results {
                    guard let dollars = Decimal(string: row.amount.value) else { continue }
                    let money = Money.fromDollars(dollars)
                    dailyTotals[day, default: .zero] += money
                    let label = [row.lineItem, row.projectId]
                        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .first { !$0.isEmpty }
                    if let label {
                        var perDay = perLineItem[label] ?? [:]
                        perDay[day, default: .zero] += money
                        perLineItem[label] = perDay
                    }
                }
            }
            guard response.hasMore, let next = response.nextPage else { break }
            page = next
        }

        let daily = dailyTotals
            .map { DailySpend(date: $0.key, cost: $0.value) }
            .sorted { $0.date < $1.date }
        var finalized = Money.zero
        for day in daily where day.date >= startOfMonth {
            finalized += day.cost
        }
        let breakdown = perLineItem
            .compactMap { label, perDay -> ModelSpend? in
                var total = Money.zero
                for (day, money) in perDay where day >= startOfMonth {
                    total += money
                }
                return total.cents > 0 ? ModelSpend(modelId: label, displayName: Self.displayName(label), cost: total) : nil
            }
            .sorted { $0.cost.cents > $1.cost.cents }

        return MTDCost(
            finalizedCost: finalized,
            todayEstimatedCost: .zero,
            unpricedModels: [],
            finalizedThrough: endExclusive,
            asOf: now,
            dailySpend: daily,
            modelBreakdown: breakdown
        )
    }

    private func costs(start: Date, end: Date, limit: Int = 30, page: String? = nil) async throws -> OpenAIAPI.CostPage {
        var query: [(String, String)] = [
            ("start_time", String(Int64(start.timeIntervalSince1970))),
            ("end_time", String(Int64(end.timeIntervalSince1970))),
            ("bucket_width", "1d"),
            ("group_by[]", "line_item"),
            ("limit", String(limit))
        ]
        if let page { query.append(("page", page)) }
        let req = try request(path: "/v1/organization/costs", queryPairs: query)
        let (data, _) = try await dataAndThrowOnHTTPError(req)
        return try decoder.decode(OpenAIAPI.CostPage.self, from: data)
    }

    private func request(path: String, queryPairs: [(String, String)]) throws -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = queryPairs.map { URLQueryItem(name: $0.0, value: $0.1) }
        guard let url = components.url else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(apiKey.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "accept")
        return req
    }

    private func dataAndThrowOnHTTPError(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, resp) = try await session.data(for: request)
        guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else {
            throw OpenAIHTTPError(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
        return (data, http)
    }

    private static func displayName(_ raw: String) -> String {
        let stripped = raw
            .replacingOccurrences(of: "model:", with: "")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
        let words = stripped.split(separator: " ")
        guard !words.isEmpty else { return raw }
        return words.map { word in
            let lower = word.lowercased()
            return lower.prefix(1).uppercased() + lower.dropFirst()
        }.joined(separator: " ")
    }

    private static func startOfMonth(utc date: Date) -> Date {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = TimeZone(identifier: "UTC")! // swiftlint:disable:this force_unwrapping
        var comps = cal.dateComponents([.year, .month], from: date)
        comps.day = 1
        return cal.date(from: comps)! // swiftlint:disable:this force_unwrapping
    }

    private static func startOfDay(utc date: Date) -> Date {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = TimeZone(identifier: "UTC")! // swiftlint:disable:this force_unwrapping
        return cal.startOfDay(for: date)
    }

    private static func addDays(_ days: Int, to date: Date) -> Date {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = TimeZone(identifier: "UTC")! // swiftlint:disable:this force_unwrapping
        return cal.date(byAdding: .day, value: days, to: date)! // swiftlint:disable:this force_unwrapping
    }
}

struct OpenAIHTTPError: LocalizedError {
    let status: Int
    let body: String
    var errorDescription: String? { "HTTP \(status): \(body.prefix(200))" }
}

func isProviderAuthError(_ error: Error) -> Bool {
    if let httpError = error as? AnthropicHTTPError, httpError.status == 401 || httpError.status == 403 { return true }
    if let httpError = error as? OpenAIHTTPError, httpError.status == 401 || httpError.status == 403 { return true }
    return false
}
