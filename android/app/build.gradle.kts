import java.util.Properties
import java.util.Base64

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasKeystoreProperties = keystorePropertiesFile.exists()

if (hasKeystoreProperties) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

android {
    namespace = "com.fieldpass.business"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.fieldpass.business"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (hasKeystoreProperties) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Use upload keystore for Play Store builds.
            signingConfig = if (hasKeystoreProperties) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

gradle.taskGraph.whenReady {
    val isReleaseTask = allTasks.any { task ->
        task.path.contains("Release", ignoreCase = true)
    }

    val dartDefinesProp = project.findProperty("dart-defines") as String?
    val decodedDartDefines = dartDefinesProp
        ?.split(',')
        ?.mapNotNull { encoded ->
            runCatching {
                String(Base64.getUrlDecoder().decode(encoded), Charsets.UTF_8)
            }.getOrNull()
        }
        ?: emptyList()

    fun hasNonPlaceholderDefine(key: String): Boolean {
        return decodedDartDefines.any { define ->
            if (!define.startsWith("$key=")) return@any false
            val value = define.substringAfter('=', "").trim()
            value.isNotEmpty() && value != key
        }
    }

    if (isReleaseTask && !hasKeystoreProperties) {
        throw org.gradle.api.GradleException(
            "Missing android/key.properties. Create it from android/key.properties.example before building a release."
        )
    }

    if (isReleaseTask) {
        val hasSupabaseUrl = hasNonPlaceholderDefine("SUPABASE_URL") ||
            hasNonPlaceholderDefine("SUPABASE_PROJECT_URL")
        val hasSupabaseAnon = hasNonPlaceholderDefine("SUPABASE_ANON_KEY") ||
            hasNonPlaceholderDefine("SUPABASE_PUBLISHABLE_KEY")

        if (!hasSupabaseUrl || !hasSupabaseAnon) {
            throw org.gradle.api.GradleException(
                "Missing release dart-defines: SUPABASE_URL and/or SUPABASE_ANON_KEY. " +
                    "Build with --dart-define-from-file=dart_defines.local.json " +
                    "or pass --dart-define SUPABASE_URL/SUPABASE_ANON_KEY explicitly."
            )
        }
    }
}

flutter {
    source = "../.."
}
