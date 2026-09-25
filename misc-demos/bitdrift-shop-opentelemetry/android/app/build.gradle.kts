import java.util.Properties

plugins {
    id("com.android.application")
    kotlin("plugin.compose")
    id("io.bitdrift.capture-plugin")
}

// Shared local.properties/.local.properties loader — also backs the capture AAR toggle
// below, so it's hoisted above the `android {}` block (mirrors bitdrift-shop/android).
val localProps = Properties()
val localPropsFile = rootProject.file("local.properties")
if (localPropsFile.exists()) localProps.load(localPropsFile.inputStream())
val privateLocalPropsFile = rootProject.file(".local.properties")
if (privateLocalPropsFile.exists()) privateLocalPropsFile.inputStream().use { localProps.load(it) }

// Flip between the published Maven Central SDK (default) and a local capture.aar under
// test: set BITDRIFT_USE_LOCAL_AAR to the AAR's full path — on the command line
// (-PBITDRIFT_USE_LOCAL_AAR=/path/to/capture.aar), in local.properties/.local.properties,
// or as an env var. Unset, blank, or "false" means "don't use it" (Maven Central); any
// other value is used directly as the AAR path.
val bitdriftLocalAarPathRaw = (
    project.findProperty("BITDRIFT_USE_LOCAL_AAR")?.toString()
        ?: localProps.getProperty("BITDRIFT_USE_LOCAL_AAR")
        ?: System.getenv("BITDRIFT_USE_LOCAL_AAR")
        ?: ""
    ).trim()
val bitdriftLocalAarPath = if (bitdriftLocalAarPathRaw.equals("false", ignoreCase = true)) "" else bitdriftLocalAarPathRaw
val bitdriftUseLocalAar = bitdriftLocalAarPath.isNotBlank()

println(
    "bitdrift capture dependency: " +
        if (bitdriftUseLocalAar) "LOCAL AAR ($bitdriftLocalAarPath)" else "Maven Central (io.bitdrift:capture:0.25.0)"
)

android {
    namespace = "com.example.shoppingdemo"
    compileSdk = 36

    defaultConfig {
        applicationId = "ai.bitdrift.oteldemo"
        minSdk = 26
        targetSdk = 36
        versionCode = 1
        versionName = "1.0"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"

        val bitdriftSdkKey = localProps.getProperty("BITDRIFT_SDK_KEY")
            ?: System.getenv("BITDRIFT_SDK_KEY")
            ?: ""
        val bitdriftApiHost = localProps.getProperty("BITDRIFT_API_HOST")
            ?: System.getenv("BITDRIFT_API_HOST")
            ?: "api.bitdrift.io"
        val otelDemoHost = localProps.getProperty("OTEL_DEMO_HOST")
            ?: System.getenv("OTEL_DEMO_HOST")
            ?: "10.0.2.2"
        val otelDemoPort = localProps.getProperty("OTEL_DEMO_PORT")
            ?: System.getenv("OTEL_DEMO_PORT")
            ?: "8081"
        // OTel span export (BIT-9050 local ClickStack demo). Blank endpoint means the
        // feature stays off (see OtelExportConfiguration wiring in ShoppingDemoApp.kt).
        val clickstackEndpoint = localProps.getProperty("CLICKSTACK_ENDPOINT")
            ?: System.getenv("CLICKSTACK_ENDPOINT")
            ?: ""
        val clickstackIngestionApiKey = localProps.getProperty("CLICKSTACK_INGESTION_API_KEY")
            ?: System.getenv("CLICKSTACK_INGESTION_API_KEY")
            ?: ""
        buildConfigField("String", "BITDRIFT_SDK_KEY", "\"$bitdriftSdkKey\"")
        buildConfigField("String", "BITDRIFT_API_HOST", "\"$bitdriftApiHost\"")
        buildConfigField("String", "OTEL_DEMO_HOST", "\"$otelDemoHost\"")
        buildConfigField("int", "OTEL_DEMO_PORT", otelDemoPort)
        buildConfigField("String", "BITDRIFT_SDK_VERSION", "\"0.25.0\"")
        buildConfigField("String", "CLICKSTACK_ENDPOINT", "\"$clickstackEndpoint\"")
        buildConfigField("String", "CLICKSTACK_INGESTION_API_KEY", "\"$clickstackIngestionApiKey\"")
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    buildFeatures {
        compose = true
        buildConfig = true
    }
}

// Workshop §1b (Automatic Network Capture): enable the Gradle plugin's automatic
// OkHttp instrumentation so every network call is captured without code changes.
// https://docs.bitdrift.io/sdk/integrations#auto-instrumentation-via-gradle-plugin
bitdrift {
    instrumentation {
        automaticOkHttpInstrumentation = false
    }
}

dependencies {
    // Workshop §1 (Quickstart): add bitdrift Android SDK dependency first.
    // Toggle via BITDRIFT_USE_LOCAL_AAR (see top of file) to test a local build of the
    // SDK against this app without editing this block.
    if (bitdriftUseLocalAar) {
        implementation(files(bitdriftLocalAarPath))

        // capture depends on the capture-sdk repo's separate :replay and :common Gradle
        // modules, which are internal-only and never published as their own Maven
        // coordinates. A bare `:capture:assembleRelease` AAR doesn't include their classes
        // at all, so their AARs must be copied and referenced alongside it (see libs/README
        // or bitdrift-shop/android/app/build.gradle.kts for the same pattern).
        implementation(files("$rootDir/libs/replay-release.aar"))
        implementation(files("$rootDir/libs/common-release.aar"))

        // capture.aar is a bare local file with no POM, so its runtime dependencies
        // (mirrored from the published capture:0.25.0 POM) must be declared explicitly.
        implementation("androidx.appcompat:appcompat:1.7.0")
        implementation("androidx.core:core:1.13.1")
        implementation("androidx.lifecycle:lifecycle-common:2.8.7")
        implementation("androidx.lifecycle:lifecycle-process:2.8.7")
        implementation("androidx.metrics:metrics-performance:1.0.0")
        implementation("androidx.startup:startup-runtime:1.2.0")
        implementation("com.google.code.gson:gson:2.11.0")
        implementation("com.google.flatbuffers:flatbuffers-java:25.2.10")
        implementation("com.google.guava:listenablefuture:1.0")
        implementation("com.google.protobuf:protobuf-kotlin-lite:4.31.1")
        // Pinned to the project's actual Kotlin compiler version, not whatever the
        // published POM declares -- see bitdrift-shop/android/app/build.gradle.kts for
        // why (stdlib/coroutines version mismatch otherwise).
        implementation("org.jetbrains.kotlin:kotlin-stdlib:2.2.10")
    } else {
        implementation("io.bitdrift:capture:0.25.0")
    }

    // OkHttp for backend API calls
    implementation("com.squareup.okhttp3:okhttp:4.12.0")

    // Coil for async image loading
    implementation("io.coil-kt:coil-compose:2.6.0")
    
    // AndroidX Core
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.appcompat)
    implementation(libs.material)

    // Jetpack Compose
    implementation(platform("androidx.compose:compose-bom:2024.12.01"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-graphics")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.navigation:navigation-compose:2.8.5")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.7")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.7")

    // Testing
    testImplementation(libs.junit)
    androidTestImplementation(libs.androidx.junit)
    androidTestImplementation(libs.androidx.espresso.core)
    androidTestImplementation(platform("androidx.compose:compose-bom:2024.12.01"))
    androidTestImplementation("androidx.compose.ui:ui-test-junit4")
    debugImplementation("androidx.compose.ui:ui-tooling")
    debugImplementation("androidx.compose.ui:ui-test-manifest")
}