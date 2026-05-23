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

    /// Returns total month-to-date cost in USD, paginating until the API runs out of pages.
    func monthToDateCost(now: Date = Date()) async throws -> Money {
        var components = Calendar(identifier: .iso8601).dateComponents(in: TimeZone(identifier: "UTC")!, from: now)
        components.day = 1
        components.hour = 0
        components.minute = 0
        components.second = 0
        components.nanosecond = 0
        guard let startOfMonth = Calendar(identifier: .iso8601).date(from: components) else {
            throw URLError(.badServerResponse)
        }
        return try await totalCost(start: startOfMonth, end: now)
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
