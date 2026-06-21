package studio.maximumimpact.tokencounter.providers.openai

import kotlinx.serialization.ExperimentalSerializationApi
import kotlinx.serialization.json.Json
import okhttp3.OkHttpClient
import retrofit2.HttpException
import retrofit2.Retrofit
import retrofit2.converter.kotlinx.serialization.asConverterFactory
import okhttp3.MediaType.Companion.toMediaType

/** Builds OpenAI API clients with bearer-token auth injected by OkHttp. */
object OpenAIClientFactory {
    const val DEFAULT_BASE_URL = "https://api.openai.com/"

    @OptIn(ExperimentalSerializationApi::class)
    private val json = Json {
        ignoreUnknownKeys = true
        explicitNulls = false
    }

    fun create(apiKey: String, baseUrl: String = DEFAULT_BASE_URL): OpenAIApi {
        val client = OkHttpClient.Builder()
            .addInterceptor { chain ->
                val request = chain.request().newBuilder()
                    .header("Authorization", "Bearer ${apiKey.trim()}")
                    .header("Accept", "application/json")
                    .build()
                chain.proceed(request)
            }
            .build()

        return Retrofit.Builder()
            .baseUrl(baseUrl)
            .client(client)
            .addConverterFactory(json.asConverterFactory("application/json".toMediaType()))
            .build()
            .create(OpenAIApi::class.java)
    }
}

/** True for HTTP 401/403 responses from OpenAI. */
fun Throwable.isOpenAIAuthError(): Boolean =
    this is HttpException && (code() == 401 || code() == 403)
