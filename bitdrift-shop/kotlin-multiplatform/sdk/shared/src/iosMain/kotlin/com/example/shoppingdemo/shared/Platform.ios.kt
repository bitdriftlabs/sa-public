package com.example.shoppingdemo.shared

import io.ktor.client.HttpClient
import io.ktor.client.engine.darwin.Darwin
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.serialization.kotlinx.json.json
import kotlinx.serialization.json.Json

actual fun platformBaseUrl(): String = "http://127.0.0.1:$BACKEND_PORT/api"

internal actual fun createPlatformHttpClient(json: Json): HttpClient = HttpClient(Darwin) {
    // Network capture on iOS is handled by URLSession swizzling in the Capture SDK,
    // initialised at the Swift layer in ShoppingDemoKMPApp.swift.
    install(ContentNegotiation) {
        json(json)
    }
}
