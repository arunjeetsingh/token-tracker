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
}
