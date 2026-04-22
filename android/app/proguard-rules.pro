# =============================================================================
# Flutter / Android release ProGuard rules for fieldpass_business
# =============================================================================
# This file is referenced by android/app/build.gradle.kts when minification
# is enabled. R8 is currently DISABLED (see build.gradle.kts release block).
# To enable, set isMinifyEnabled = true and isShrinkResources = true in the
# release buildType, then run a full release build and test on a real device
# before publishing.
# =============================================================================

# --- Flutter core --------------------------------------------------------
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }
-keep class io.flutter.embedding.** { *; }
-dontwarn io.flutter.embedding.**

# --- Plugins this project uses ------------------------------------------
# flutter_secure_storage
-keep class com.it_nomads.fluttersecurestorage.** { *; }
# image_picker
-keep class io.flutter.plugins.imagepicker.** { *; }
# shared_preferences
-keep class io.flutter.plugins.sharedpreferences.** { *; }
# url_launcher
-keep class io.flutter.plugins.urllauncher.** { *; }
# path_provider
-keep class io.flutter.plugins.pathprovider.** { *; }
# app_links (used for OAuth deep links)
-keep class com.llfbandit.app_links.** { *; }

# --- Firebase / Google services (project applies google-services plugin) -
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-keep class com.google.android.gms.common.** { *; }
-keep class com.google.android.gms.auth.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# --- Play Core (Flutter uses for deferred components, even when you don't) -
-keep class com.google.android.play.core.** { *; }
-dontwarn com.google.android.play.core.**

# --- Kotlin runtime + coroutines ----------------------------------------
-keep class kotlin.** { *; }
-keep class kotlinx.coroutines.** { *; }
-dontwarn kotlin.**
-dontwarn kotlinx.coroutines.**

# --- AndroidX security-crypto (used by flutter_secure_storage v9) -------
-keep class androidx.security.crypto.** { *; }
-dontwarn androidx.security.crypto.**

# --- Keep annotations, generics, exceptions for stack traces ------------
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes InnerClasses
-keepattributes EnclosingMethod
-keepattributes Exceptions
-keepattributes SourceFile
-keepattributes LineNumberTable

# --- Optional / transitive deps that may not be on classpath ------------
-dontwarn org.bouncycastle.**
-dontwarn org.conscrypt.**
-dontwarn org.openjsse.**
-dontwarn javax.annotation.**

# --- Keep R class fields (resource ids referenced via reflection) -------
-keepclassmembers class **.R$* {
    public static <fields>;
}

# --- Keep native methods -------------------------------------------------
-keepclasseswithmembernames class * {
    native <methods>;
}

# --- Keep custom Application / Activity entry points --------------------
-keep public class * extends android.app.Application
-keep public class * extends android.app.Activity
-keep public class * extends android.app.Service
-keep public class * extends android.content.BroadcastReceiver
-keep public class * extends android.content.ContentProvider
