import java.util.Properties

// bitdrift SDK plugin

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
    id("io.bitdrift.capture-plugin") version "0.23.10"
}

android {
    namespace = "ai.bitdrift.metricdemo"
    compileSdk = 36

    defaultConfig {
        applicationId = "ai.bitdrift.metricdemo"
        minSdk = 26
        targetSdk = 36
        versionCode = 1
        versionName = "1.0"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"

        val localProps = Properties()
        val localPropsFile = rootProject.file("local.properties")
        if (localPropsFile.exists()) localProps.load(localPropsFile.inputStream())
        val privateLocalPropsFile = rootProject.file(".local.properties")
        if (privateLocalPropsFile.exists()) privateLocalPropsFile.inputStream().use { localProps.load(it) }
        val bitdriftSdkKey = localProps.getProperty("BITDRIFT_SDK_KEY")
            ?: System.getenv("BITDRIFT_SDK_KEY")
            ?: ""
        val bitdriftApiHost = localProps.getProperty("BITDRIFT_API_HOST")
            ?: System.getenv("BITDRIFT_API_HOST")
            ?: "api.bitdrift.io"
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
    kotlin {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
    }
    buildFeatures {
        compose = true
        buildConfig = true
    }
}

dependencies {
    // bitdrift SDK 
    implementation("io.bitdrift:capture:0.23.10")

    // OkHttp (for HttpUrl used in Logger.start apiUrl)
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    
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

bitdrift {
    instrumentation {
        automaticOkHttpInstrumentation = true
    }
}