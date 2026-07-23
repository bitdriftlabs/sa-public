import java.util.Properties

plugins {
    id("com.android.application")
    kotlin("plugin.compose")
    id("io.bitdrift.capture-plugin")
}

// Shared local.properties/.local.properties loader — also backs the capture
// AAR toggle below, so it's hoisted above the `android {}` block.
val localProps = Properties()
val localPropsFile = rootProject.file("local.properties")
if (localPropsFile.exists()) localProps.load(localPropsFile.inputStream())
val privateLocalPropsFile = rootProject.file(".local.properties")
if (privateLocalPropsFile.exists()) privateLocalPropsFile.inputStream().use { localProps.load(it) }

// Flip between the published Maven Central SDK (default) and a local capture.aar
// under test: set BITDRIFT_USE_LOCAL_AAR to the AAR's full path — on the command
// line (-PBITDRIFT_USE_LOCAL_AAR=/path/to/capture.aar), in local.properties/
// .local.properties, or as an env var. Unset, blank, or "false" means "don't use
// it" (Maven Central); any other value is used directly as the AAR path.
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
        if (bitdriftUseLocalAar) "LOCAL AAR ($bitdriftLocalAarPath)" else "Maven Central (io.bitdrift:capture:0.23.10)"
)

android {
    namespace = "ai.bitdrift.shop"
    compileSdk = 36

    defaultConfig {
        applicationId = "ai.bitdrift.shop"
        minSdk = 26
        targetSdk = 36
        versionCode = 9
        versionName = "4.1"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"

        val bitdriftSdkKey = localProps.getProperty("BITDRIFT_SDK_KEY")
            ?: System.getenv("BITDRIFT_SDK_KEY")
            ?: ""
        val bitdriftApiHost = localProps.getProperty("BITDRIFT_API_HOST")
            ?: System.getenv("BITDRIFT_API_HOST")
            ?: "api.bitdrift.io"
        buildConfigField("String", "BITDRIFT_SDK_KEY", "\"$bitdriftSdkKey\"")
        buildConfigField("String", "BITDRIFT_API_HOST", "\"$bitdriftApiHost\"")
        buildConfigField("boolean", "SHOW_CARDINALITY", project.findProperty("SHOW_CARDINALITY")?.toString() ?: "false")
        buildConfigField("boolean", "SHOW_SIM_AB", project.findProperty("SHOW_SIM_AB")?.toString() ?: "false")
        // Surfaced in the UI (see Components.kt) so it's obvious at a glance which
        // capture dependency a given build/install was made with.
        buildConfigField("String", "BITDRIFT_CAPTURE_SOURCE", "\"${if (bitdriftUseLocalAar) "AAR" else "SDK"}\"")
        buildConfigField(
            "String",
            "BITDRIFT_LOCAL_AAR_NAME",
            "\"${if (bitdriftUseLocalAar) File(bitdriftLocalAarPath).name else ""}\""
        )
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
        automaticOkHttpInstrumentation = true
    }
}

dependencies {
    // Workshop §1 (Quickstart): add bitdrift Android SDK dependency first.
    // Toggle via bitdriftUseLocalAar (see top of file) to test a local build
    // of the SDK against this app without editing this block.
    if (bitdriftUseLocalAar) {
        implementation(files(bitdriftLocalAarPath))

        // capture.aar is a bare local file with no POM, so its runtime dependencies
        // (mirrored from the published capture:0.23.10 POM) must be declared explicitly.
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
        // Pinned to the project's actual Kotlin compiler version (see root
        // build.gradle.kts), not the 1.9.25 the published POM declares: in Maven
        // Central mode the capture-plugin detects the io.bitdrift:capture
        // coordinate and aligns kotlin-stdlib to the compiler version itself, but
        // that alignment doesn't kick in for this bare local file dependency,
        // leaving stdlib on 2.0.21 — missing kotlin.coroutines.jvm.internal.SpillingKt
        // that 2.2.10-compiled suspend functions call into (NoClassDefFoundError).
        implementation("org.jetbrains.kotlin:kotlin-stdlib:2.2.10")
    } else {
        implementation("io.bitdrift:capture:0.23.10")
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

// Force a full uninstall before every debug install (Android Studio Run/Debug or
// `./gradlew installDebug`), so no stale APK/class data can linger between builds —
// a stale install once masked a real code change during crash-loop testing.
tasks.matching { it.name == "installDebug" }.configureEach {
    doFirst {
        val adb = System.getenv("ANDROID_HOME")?.let { "$it/platform-tools/adb" }
            ?: System.getenv("ANDROID_SDK_ROOT")?.let { "$it/platform-tools/adb" }
            ?: "adb"
        // Plain ProcessBuilder, not Project.exec — the latter was removed in Gradle 9
        // in favor of injected ExecOperations, which is more ceremony than this needs.
        // Exit code intentionally ignored: fails harmlessly if not yet installed.
        ProcessBuilder(adb, "uninstall", "ai.bitdrift.shop")
            .redirectErrorStream(true)
            .start()
            .waitFor()
    }
}