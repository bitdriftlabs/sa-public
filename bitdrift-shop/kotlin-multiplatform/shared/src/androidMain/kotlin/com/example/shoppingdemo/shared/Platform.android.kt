package com.example.shoppingdemo.shared

import io.bitdrift.capture.network.okhttp.CaptureOkHttpEventListenerFactory
import io.ktor.client.HttpClient
import io.ktor.client.engine.okhttp.OkHttp
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.serialization.kotlinx.json.json
import kotlinx.serialization.json.Json
import okhttp3.OkHttpClient

actual fun platformBaseUrl(): String = "http://10.0.2.2:$BACKEND_PORT/api"

internal actual fun createPlatformHttpClient(json: Json): HttpClient = HttpClient(OkHttp) {
    engine {
        preconfigured = OkHttpClient.Builder()
            .eventListenerFactory(CaptureOkHttpEventListenerFactory())
            .build()
    }
    install(ContentNegotiation) {
        json(json)
    }
}
