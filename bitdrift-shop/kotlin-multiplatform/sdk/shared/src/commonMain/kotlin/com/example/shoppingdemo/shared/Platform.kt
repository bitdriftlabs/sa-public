package com.example.shoppingdemo.shared

import io.ktor.client.HttpClient
import kotlinx.serialization.json.Json

/**
 * Platform-specific base URL for the backend API.
 * Android emulator uses 10.0.2.2 to reach the host machine.
 * iOS simulator uses 127.0.0.1.
 */
const val BACKEND_PORT = 5173

expect fun platformBaseUrl(): String

/**
 * Creates the platform-specific Ktor HttpClient.
 * Android: OkHttp engine with CaptureOkHttpEventListenerFactory for automatic network logging.
 * iOS: Darwin engine (network capture is handled by URLSession swizzling at the Swift layer).
 */
internal expect fun createPlatformHttpClient(json: Json): HttpClient
