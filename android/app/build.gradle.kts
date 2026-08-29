import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.example.capcut_video_editor"
    compileSdk = 34
    buildToolsVersion = "34.0.0"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.example.capcut_video_editor"
        minSdk = 24
        targetSdk = 34
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            val keyAliasProp = keystoreProperties.getProperty("keyAlias") ?: System.getenv("ANDROID_KEY_ALIAS")
            val keyPasswordProp = keystoreProperties.getProperty("keyPassword") ?: System.getenv("ANDROID_KEY_PASSWORD")
            val storeFileProp = keystoreProperties.getProperty("storeFile") ?: System.getenv("ANDROID_STORE_FILE")
            val storePasswordProp = keystoreProperties.getProperty("storePassword") ?: System.getenv("ANDROID_STORE_PASSWORD")

            if (!keyAliasProp.isNullOrBlank() &&
                !keyPasswordProp.isNullOrBlank() &&
                !storeFileProp.isNullOrBlank() &&
                !storePasswordProp.isNullOrBlank()) {
                val resolvedStoreFile = if (file(storeFileProp).isAbsolute) {
                    file(storeFileProp)
                } else {
                    rootProject.file(storeFileProp)
                }
                if (resolvedStoreFile.exists()) {
                    keyAlias = keyAliasProp
                    keyPassword = keyPasswordProp
                    storeFile = resolvedStoreFile
                    storePassword = storePasswordProp
                } else {
                    val debugConfig = signingConfigs.getByName("debug")
                    keyAlias = debugConfig.keyAlias
                    keyPassword = debugConfig.keyPassword
                    storeFile = debugConfig.storeFile
                    storePassword = debugConfig.storePassword
                }
            } else {
                val debugConfig = signingConfigs.getByName("debug")
                keyAlias = debugConfig.keyAlias
                keyPassword = debugConfig.keyPassword
                storeFile = debugConfig.storeFile
                storePassword = debugConfig.storePassword
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
        debug {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
