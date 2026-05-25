import Foundation

/// Wire types for the Anthropic Usage & Cost Admin API.
enum AnthropicAPI {
    struct OrgIdentity: Decodable {
        let id: String
        let type: String
        let name: String
    }

    struct CostReportPage: Decodable {
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
        let startingAt: Date
        let endingAt: Date
        let results: [CostRow]

        enum CodingKeys: String, CodingKey {
            case startingAt = "starting_at"
            case endingAt = "ending_at"
            case results
        }
    }

    struct CostRow: Decodable {
        let currency: String
        /// Amount in cents USD as a numeric string (e.g. "2013.9595").
        let amount: String
        let workspaceId: String?
        let model: String?
        let serviceTier: String?
        let tokenType: String?
        let costType: String?
        let contextWindow: String?
        let inferenceGeo: String?
        let description: String?

        enum CodingKeys: String, CodingKey {
            case currency
            case amount
            case workspaceId = "workspace_id"
            case model
            case serviceTier = "service_tier"
            case tokenType = "token_type"
            case costType = "cost_type"
            case contextWindow = "context_window"
            case inferenceGeo = "inference_geo"
            case description
        }
    }

    // MARK: - usage_report/messages

    /// One page from `/v1/organizations/usage_report/messages`.
    struct MessagesUsagePage: Decodable {
        let data: [MessagesUsageBucket]
        let hasMore: Bool
        let nextPage: String?

        enum CodingKeys: String, CodingKey {
            case data
            case hasMore = "has_more"
            case nextPage = "next_page"
        }
    }

    struct MessagesUsageBucket: Decodable {
        let startingAt: Date
        let endingAt: Date
        let results: [MessagesUsageRow]

        enum CodingKeys: String, CodingKey {
            case startingAt = "starting_at"
            case endingAt = "ending_at"
            case results
        }
    }

    /// One usage row. All fields except token counts may be null when the
    /// corresponding group_by[] dimension isn't requested.
    struct MessagesUsageRow: Decodable {
        let model: String?
        let uncachedInputTokens: Int
        let cacheCreation: CacheCreation
        let cacheReadInputTokens: Int
        let outputTokens: Int

        enum CodingKeys: String, CodingKey {
            case model
            case uncachedInputTokens = "uncached_input_tokens"
            case cacheCreation = "cache_creation"
            case cacheReadInputTokens = "cache_read_input_tokens"
            case outputTokens = "output_tokens"
        }
    }

    struct CacheCreation: Decodable {
        let ephemeral5mInputTokens: Int
        let ephemeral1hInputTokens: Int

        enum CodingKeys: String, CodingKey {
            case ephemeral5mInputTokens = "ephemeral_5m_input_tokens"
            case ephemeral1hInputTokens = "ephemeral_1h_input_tokens"
        }
    }
}
