import java.util.Properties

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.bitdrift.capture.plugin)
}

android {
    namespace = "ai.bitdrift.shop"
    compileSdk = 35

    defaultConfig {
        applicationId = "ai.bitdrift.shop.kmp"
        minSdk = 26
        targetSdk = 35
        versionCode = 1
        versionName = "1.0"

        val localProps = Properties()
        val localPropsFile = rootProject.file("local.properties")
        if (localPropsFile.exists()) localProps.load(localPropsFile.inputStream())
        val privateLocalPropsFile = rootProject.file(".local.properties")
        if (privateLocalPropsFile.exists()) privateLocalPropsFile.inputStream().use { localProps.load(it) }
        val bitdriftSdkKey = localProps.getProperty("BITDRIFT_SDK_KEY")
            ?: System.getenv("BITDRIFT_SDK_KEY") ?: ""
        val bitdriftApiHost = localProps.getProperty("BITDRIFT_API_HOST")
            ?: System.getenv("BITDRIFT_API_HOST") ?: "api.bitdrift.io"
        buildConfigField("String", "BITDRIFT_SDK_KEY", "\"$bitdriftSdkKey\"")
        buildConfigField("String", "BITDRIFT_API_HOST", "\"$bitdriftApiHost\"")
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
    kotlinOptions {
        jvmTarget = "17"
    }
    buildFeatures {
        compose = true
        buildConfig = true
    }
}

// Attach Capture's OkHttp event listener to every OkHttp client in the app
// automatically — no per-call code changes required.
bitdrift {
    instrumentation {
        automaticOkHttpInstrumentation = true
    }
}

dependencies {
    implementation(project(":shared"))

    // bitdrift Capture SDK
    implementation(libs.bitdrift.capture)

    // Coil for async image loading
    implementation(libs.coil.compose)

    // AndroidX Core
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.navigation.compose)

    // Jetpack Compose
    implementation(platform(libs.compose.bom))
    implementation(libs.compose.ui)
    implementation(libs.compose.ui.graphics)
    implementation(libs.compose.ui.tooling.preview)
    implementation(libs.compose.material3)
    implementation(libs.compose.material.icons.extended)

    debugImplementation(libs.compose.ui.tooling)
}
