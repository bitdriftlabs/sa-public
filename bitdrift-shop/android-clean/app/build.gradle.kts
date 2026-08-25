import java.util.Properties

plugins {
    id("com.android.application")
    kotlin("plugin.compose")
}

// Shared local.properties/.local.properties loader.
val localProps = Properties()
val localPropsFile = rootProject.file("local.properties")
if (localPropsFile.exists()) localProps.load(localPropsFile.inputStream())
val privateLocalPropsFile = rootProject.file(".local.properties")
if (privateLocalPropsFile.exists()) privateLocalPropsFile.inputStream().use { localProps.load(it) }
val shopBackendUrl = localProps.getProperty("SHOP_BACKEND_URL", "http://10.0.2.2:5173")

android {
    namespace = "ai.bitdrift.shop"
    compileSdk = 36

    defaultConfig {
        applicationId = "ai.bitdrift.shop"
        minSdk = 26
        targetSdk = 36
        versionCode = 11
        versionName = "4.3"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"

        buildConfigField("boolean", "SHOW_CARDINALITY", project.findProperty("SHOW_CARDINALITY")?.toString() ?: "false")
        buildConfigField("boolean", "SHOW_SIM_AB", project.findProperty("SHOW_SIM_AB")?.toString() ?: "false")
        buildConfigField("String", "SHOP_BACKEND_URL", "\"$shopBackendUrl\"")
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

dependencies {
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
