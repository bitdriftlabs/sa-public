package ai.bitdrift.shop

import io.bitdrift.capture.Configuration

// Compiled when BITDRIFT_ENABLE_OTEL_EXPORT is off (see app/build.gradle.kts) -- e.g. testing
// against the published io.bitdrift:capture Maven Central SDK, which doesn't have
// OtelExportConfiguration at all.
internal fun buildBitdriftConfiguration(): Configuration = Configuration()
