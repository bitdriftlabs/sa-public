# Add project specific ProGuard rules here.
# You can control the set of applied configuration files using the
# proguardFiles setting in build.gradle.
#
# For more details, see
#   http://developer.android.com/guide/developing/tools/proguard.html

# If your project uses WebView with JS, uncomment the following
# and specify the fully qualified class name to the JavaScript interface
# class:
#-keepclassmembers class fqcn.of.javascript.interface.for.webview {
#   public *;
#}

# Preserve line number information for bitdrift crash stack traces.
-keepattributes SourceFile,LineNumberTable

# If you keep the line number information, uncomment this to
# hide the original source file name.
#-renamesourcefileattribute SourceFile
# Realistic crash sites: keep them as distinct, non-inlined methods so the symbolicated top frame
# is the app class (CartPricing / PromoBannerParser) rather than a merged synthetic accessor.
-keep class ai.bitdrift.shop.CartPricing { *; }
-keep class ai.bitdrift.shop.PromoBannerParser { *; }
