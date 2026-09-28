package ai.bitdrift.shop

import io.bitdrift.capture.Configuration
import io.bitdrift.capture.experimental.ExperimentalBitdriftApi
import io.bitdrift.capture.network.okhttp.otel.OtelExportConfiguration
import okhttp3.HttpUrl.Companion.toHttpUrl

// Compiled only when BITDRIFT_ENABLE_OTEL_EXPORT is on (see app/build.gradle.kts) --
// OtelExportConfiguration only exists in the local capture-sdk AAR (BIT-9050 branch), not in the
// published io.bitdrift:capture Maven Central artifact.
@OptIn(ExperimentalBitdriftApi::class)
internal fun buildBitdriftConfiguration(): Configuration {
    // otelExportConfiguration (BIT-9050 local ClickStack demo): only set when both
    // CLICKSTACK_ENDPOINT and CLICKSTACK_INGESTION_API_KEY are configured (.local.properties /
    // env var) -- an endpoint with no key would otherwise construct an exporter that repeatedly
    // sends unauthenticated requests instead of staying off.
    val otelExportConfiguration =
        if (BuildConfig.CLICKSTACK_ENDPOINT.isNotBlank() && BuildConfig.CLICKSTACK_INGESTION_API_KEY.isNotBlank()) {
            OtelExportConfiguration(
                endpoint = BuildConfig.CLICKSTACK_ENDPOINT.toHttpUrl(),
                authHeaderValue = BuildConfig.CLICKSTACK_INGESTION_API_KEY,
            )
        } else {
            null
        }
    return Configuration(otelExportConfiguration = otelExportConfiguration)
}
