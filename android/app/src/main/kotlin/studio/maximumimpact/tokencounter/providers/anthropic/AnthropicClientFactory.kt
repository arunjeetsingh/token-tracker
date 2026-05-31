package studio.maximumimpact.tokencounter.providers.anthropic

import kotlinx.serialization.json.Json
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import retrofit2.HttpException
import retrofit2.Retrofit
import retrofit2.converter.kotlinx.serialization.asConverterFactory

/**
 * Builds [AnthropicApi] instances wired to a given admin key. The auth and
 * version headers are injected by an OkHttp interceptor so they don't have to
 * be threaded through every call. A fresh client per key is cheap — the JSON
 * codec is shared.
 */
object AnthropicClientFactory {

    const val DEFAULT_BASE_URL = "https://api.anthropic.com/"
    private const val API_VERSION = "2023-06-01"

    private val json = Json {
        ignoreUnknownKeys = true
        explicitNulls = false
    }

    fun create(apiKey: String, baseUrl: String = DEFAULT_BASE_URL): AnthropicApi {
        val httpClient = OkHttpClient.Builder()
            .addInterceptor { chain ->
                val request = chain.request().newBuilder()
                    .header("x-api-key", apiKey)
                    .header("anthropic-version", API_VERSION)
                    .header("accept", "application/json")
                    .build()
                chain.proceed(request)
            }
            .build()

        return Retrofit.Builder()
            .baseUrl(baseUrl)
            .client(httpClient)
            .addConverterFactory(json.asConverterFactory("application/json".toMediaType()))
            .build()
            .create(AnthropicApi::class.java)
    }
}

/**
 * True for HTTP 401/403 responses — the admin key was rejected. The caller
 * wipes the stored key and re-onboards rather than showing a transient error.
 */
fun Throwable.isAnthropicAuthError(): Boolean =
    this is HttpException && (code() == 401 || code() == 403)
