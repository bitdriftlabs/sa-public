// Top-level build file where you can add configuration options common to all sub-projects/modules.
plugins {
    alias(libs.plugins.android.application) apply false
    kotlin("android") version "2.2.10" apply false
    kotlin("plugin.compose") version "2.2.10" apply false
    id("io.bitdrift.capture-plugin") version "0.23.6" apply false
}