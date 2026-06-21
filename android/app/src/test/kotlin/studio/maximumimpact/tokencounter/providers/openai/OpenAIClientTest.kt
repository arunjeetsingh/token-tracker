package studio.maximumimpact.tokencounter.providers.openai

import kotlinx.coroutines.test.runTest
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import retrofit2.HttpException
import studio.maximumimpact.tokencounter.core.Money
import studio.maximumimpact.tokencounter.providers.ProviderKind
import studio.maximumimpact.tokencounter.providers.providerKindFor
import java.time.Instant
import java.time.LocalDate

/**
 * Exercises [OpenAIClient] against a [MockWebServer]: auth headers, query
 * shape, pagination, USD amount conversion, and shared auth-error detection.
 */
class OpenAIClientTest {

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

    private fun client(): OpenAIClient =
        OpenAIClient(OpenAIClientFactory.create(apiKey = " [REDACTED] ", baseUrl = server.url("/").toString()))

    @Test
    fun providerKindFor_routesAnthropicPrefixAndDefaultsToOpenAI() {
        assertEquals(ProviderKind.ANTHROPIC, providerKindFor("  sk-ant-[REDACTED]  "))
        assertEquals(ProviderKind.OPENAI, providerKindFor("[REDACTED]"))
    }

    @Test
    fun whoami_probesCostsEndpointWithBearerAuth() = runTest {
        server.enqueue(
            MockResponse().setBody(
                """{"data":[],"has_more":false,"next_page":null}"""
            )
        )

        val org = client().whoami(Instant.parse("2026-05-30T12:00:00Z"))

        assertEquals("OpenAI Organization", org.name)
        assertEquals("openai", org.id)
        val request = server.takeRequest()
        assertEquals("Bearer [REDACTED]", request.getHeader("Authorization"))
        assertEquals("application/json", request.getHeader("Accept"))
        assertEquals("/v1/organization/costs", request.requestUrl!!.encodedPath)
        assertEquals("1780099200", request.requestUrl!!.queryParameter("start_time"))
        assertEquals("1780185600", request.requestUrl!!.queryParameter("end_time"))
        assertEquals("1d", request.requestUrl!!.queryParameter("bucket_width"))
        assertEquals("line_item", request.requestUrl!!.queryParameterValues("group_by[]").single())
        assertEquals("1", request.requestUrl!!.queryParameter("limit"))
    }

    @Test
    fun monthToDateCost_convertsUsdAmountsAndBuildsDailyAndBreakdown() = runTest {
        server.enqueue(
            MockResponse().setBody(
                """
                {
                  "data": [
                    {"start_time":1777507200,"end_time":1777593600,"results":[
                      {"amount":{"value":"99.99","currency":"usd"},"line_item":"model:gpt-4.1"}
                    ]},
                    {"start_time":1780012800,"end_time":1780099200,"results":[
                      {"amount":{"value":"12.345","currency":"usd"},"line_item":"model:gpt-4.1"},
                      {"amount":{"value":"0.335","currency":"usd"},"line_item":"batch_api"},
                      {"amount":{"value":"4.00","currency":"usd"},"line_item":null,"project_id":"proj_alpha"}
                    ]},
                    {"start_time":1780099200,"end_time":1780185600,"results":[
                      {"amount":{"value":"20.00","currency":"usd"},"line_item":"model:gpt-4o-mini"}
                    ]}
                  ],
                  "has_more": false,
                  "next_page": null
                }
                """.trimIndent()
            )
        )

        val report = client().monthToDateCost(Instant.parse("2026-05-30T12:00:00Z"))

        // Prior-month sparkline row is kept in dailySpend but excluded from MTD.
        assertEquals(3, report.dailySpend.size)
        assertEquals(LocalDate.of(2026, 4, 30), report.dailySpend.first().date)
        // MTD = 12.345 -> 1234¢ (bankers), 0.335 -> 34¢, 4.00 -> 400¢, 20.00 -> 2000¢.
        assertEquals(Money(3668), report.finalizedCost)
        assertEquals(Money.Zero, report.todayEstimatedCost)
        assertEquals(LocalDate.of(2026, 5, 31), report.finalizedThrough)
        assertEquals(emptyList<String>(), report.unpricedModels)

        assertEquals(4, report.modelBreakdown.size)
        assertEquals("model:gpt-4o-mini", report.modelBreakdown[0].modelId)
        assertEquals("GPT 4o Mini", report.modelBreakdown[0].displayName)
        assertEquals(Money(2000), report.modelBreakdown[0].cost)
        assertEquals("model:gpt-4.1", report.modelBreakdown[1].modelId)
        assertEquals(Money(1234), report.modelBreakdown[1].cost)
        assertEquals("proj_alpha", report.modelBreakdown[2].modelId)
        assertEquals(Money(400), report.modelBreakdown[2].cost)
        assertEquals("batch_api", report.modelBreakdown[3].modelId)
        assertEquals("Batch API", report.modelBreakdown[3].displayName)
        assertEquals(Money(34), report.modelBreakdown[3].cost)
    }

    @Test
    fun monthToDateCost_followsPaginationAcrossPages() = runTest {
        server.enqueue(
            MockResponse().setBody(
                """
                {
                  "data": [
                    {"start_time":1780876800,"results":[
                      {"amount":{"value":"1.00","currency":"usd"},"line_item":"model:gpt-4.1"}
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
                    {"start_time":1780876800,"results":[
                      {"amount":{"value":"2.00","currency":"usd"},"line_item":"model:gpt-4.1"}
                    ]}
                  ],
                  "has_more": false,
                  "next_page": null
                }
                """.trimIndent()
            )
        )

        val report = client().monthToDateCost(Instant.parse("2026-06-08T12:00:00Z"))

        assertEquals(Money(300), report.finalizedCost)
        assertEquals(2, server.requestCount)
        server.takeRequest()
        val second = server.takeRequest()
        assertEquals("page_2", second.requestUrl!!.queryParameter("page"))
    }

    @Test
    fun http401IsOpenAIAuthError() = runTest {
        server.enqueue(MockResponse().setResponseCode(401).setBody("{\"error\":\"unauthorized\"}"))

        try {
            client().whoami(Instant.parse("2026-05-30T12:00:00Z"))
            throw AssertionError("expected error")
        } catch (error: HttpException) {
            assertTrue(error.isOpenAIAuthError())
        }
    }
}
