package studio.maximumimpact.tokencounter.providers.anthropic

import kotlinx.coroutines.test.runTest
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import studio.maximumimpact.tokencounter.core.Money
import java.time.Instant
import java.time.LocalDate

/**
 * Exercises [AnthropicClient] end-to-end against a [MockWebServer]: JSON
 * decoding, pagination, the finalized-vs-today split, and the pricing-based
 * today estimate.
 */
class AnthropicClientTest {

    private lateinit var server: MockWebServer

    @Before
    fun setUp() {
        server = MockWebServer()
        server.start()
    }

    @After
    fun tearDown() {
        server.shutdown()
    }

    private fun client(): AnthropicClient =
        AnthropicClient(AnthropicClientFactory.create(apiKey = "sk-ant-admin01-test", baseUrl = server.url("/").toString()))

    @Test
    fun whoami_decodesOrgIdentity() = runTest {
        server.enqueue(
            MockResponse().setBody(
                """{"id":"org_123","type":"organization","name":"Acme Inc"}"""
            )
        )
        val org = client().whoami()
        assertEquals("Acme Inc", org.name)
        assertEquals("org_123", org.id)
    }

    @Test
    fun monthToDateCost_splitsFinalizedAndTodayAndBuildsBreakdown() = runTest {
        // cost_report: one in-month day, one more in-month day, one prior-month
        // day (must be excluded from finalized + breakdown, kept in dailySpend).
        server.enqueue(
            MockResponse().setBody(
                """
                {
                  "data": [
                    {"starting_at":"2026-04-30T00:00:00Z","results":[
                      {"amount":"9999.0","model":"claude-opus-4-5","currency":"USD"}
                    ]},
                    {"starting_at":"2026-05-28T00:00:00Z","results":[
                      {"amount":"1000.0","model":"claude-opus-4-5"},
                      {"amount":"500.0","model":"claude-sonnet-4-5"},
                      {"amount":"50.0","model":null,"description":"web_search"}
                    ]},
                    {"starting_at":"2026-05-29T00:00:00Z","results":[
                      {"amount":"2000.0","model":"claude-opus-4-5"}
                    ]}
                  ],
                  "has_more": false,
                  "next_page": null
                }
                """.trimIndent()
            )
        )
        // usage_report: priced model (opus) + an unpriced one.
        server.enqueue(
            MockResponse().setBody(
                """
                {
                  "data": [
                    {"starting_at":"2026-05-30T00:00:00Z","results":[
                      {"model":"claude-opus-4-5","uncached_input_tokens":1000000,"output_tokens":1000000,
                       "cache_creation":{"ephemeral_5m_input_tokens":0,"ephemeral_1h_input_tokens":0},
                       "cache_read_input_tokens":0},
                      {"model":"mystery-model","uncached_input_tokens":0,"output_tokens":500000,
                       "cache_creation":{"ephemeral_5m_input_tokens":0,"ephemeral_1h_input_tokens":0},
                       "cache_read_input_tokens":0}
                    ]}
                  ],
                  "has_more": false
                }
                """.trimIndent()
            )
        )

        val now = Instant.parse("2026-05-30T12:00:00Z")
        val report = client().monthToDateCost(now)

        // Finalized = in-month days only: 1550 + 2000 = 3550¢.
        assertEquals(Money(3550), report.finalizedCost)
        // Today = 1M input ($5) + 1M output ($25) on Opus = $30.00 = 3000¢.
        assertEquals(Money(3000), report.todayEstimatedCost)
        assertEquals(Money(6550), report.total)
        assertEquals(LocalDate.of(2026, 5, 30), report.finalizedThrough)

        // dailySpend keeps all 3 days (incl. prior-month), sorted ascending.
        assertEquals(3, report.dailySpend.size)
        assertEquals(LocalDate.of(2026, 4, 30), report.dailySpend.first().date)

        // Breakdown is in-month, sorted desc: opus 3000, sonnet 500.
        assertEquals(2, report.modelBreakdown.size)
        assertEquals("Claude Opus 4.5", report.modelBreakdown[0].displayName)
        assertEquals(Money(3000), report.modelBreakdown[0].cost)
        assertEquals(Money(500), report.modelBreakdown[1].cost)

        // The unpriced model is surfaced.
        assertEquals(listOf("mystery-model"), report.unpricedModels)
        assertTrue(report.hasUnpricedModels)
    }

    @Test
    fun costDetail_followsPaginationAcrossPages() = runTest {
        server.enqueue(
            MockResponse().setBody(
                """
                {
                  "data": [
                    {"starting_at":"2026-05-10T00:00:00Z","results":[
                      {"amount":"100.0","model":"claude-opus-4-5"}
                    ]}
                  ],
                  "has_more": true,
                  "next_page": "page_2"
                }
                """.trimIndent()
            )
        )
        server.enqueue(
            MockResponse().setBody(
                """
                {
                  "data": [
                    {"starting_at":"2026-05-10T00:00:00Z","results":[
                      {"amount":"25.0","model":"claude-opus-4-5"}
                    ]}
                  ],
                  "has_more": false,
                  "next_page": null
                }
                """.trimIndent()
            )
        )

        val detail = client().costDetail(
            start = LocalDate.of(2026, 5, 1),
            endExclusive = LocalDate.of(2026, 5, 30)
        )

        // Same day across two pages folds together: 100 + 25 = 125¢.
        assertEquals(1, detail.daily.size)
        assertEquals(Money(125), detail.daily.first().cost)
        assertEquals(2, server.requestCount)
        // The second request carried the page token.
        server.takeRequest()
        val second = server.takeRequest()
        assertTrue(second.requestUrl!!.queryParameter("page") == "page_2")
    }
}
