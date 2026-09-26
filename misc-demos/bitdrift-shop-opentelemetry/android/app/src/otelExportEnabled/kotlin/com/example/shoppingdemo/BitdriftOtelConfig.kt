package com.example.shoppingdemo

import io.bitdrift.capture.Configuration
import io.bitdrift.capture.experimental.ExperimentalBitdriftApi
import io.bitdrift.capture.network.okhttp.otel.OtelExportConfiguration
import okhttp3.HttpUrl.Companion.toHttpUrl

// Compiled only when BITDRIFT_ENABLE_OTEL_EXPORT is on (see app/build.gradle.kts) --
// OtelExportConfiguration only exists in the local capture-sdk AAR (BIT-9050 branch), not in the
// published io.bitdrift:capture Maven Central artifact.
@OptIn(ExperimentalBitdriftApi::class)
internal fun buildBitdriftConfiguration(): Configuration {
    // otelExportConfiguration (BIT-9050 local ClickStack demo): only set when CLICKSTACK_ENDPOINT
    // is configured (.local.properties / env var), so the feature stays off by default rather
    // than pointing at a blank URL.
    val otelExportConfiguration =
        BuildConfig.CLICKSTACK_ENDPOINT.takeIf { it.isNotBlank() }?.let { endpoint ->
            OtelExportConfiguration(
                endpoint = endpoint.toHttpUrl(),
                authHeaderValue = BuildConfig.CLICKSTACK_INGESTION_API_KEY,
            )
        }
    return Configuration(otelExportConfiguration = otelExportConfiguration)
}
