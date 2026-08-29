import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val appKeystorePropertiesFile = file("key.properties")
val actualPropertiesFile = when {
    keystorePropertiesFile.exists() -> keystorePropertiesFile
    appKeystorePropertiesFile.exists() -> appKeystorePropertiesFile
    else -> null
}

if (actualPropertiesFile != null) {
    keystoreProperties.load(FileInputStream(actualPropertiesFile))
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
                val resolvedStoreFile = when {
                    file(storeFileProp).isAbsolute && file(storeFileProp).exists() -> file(storeFileProp)
                    file(storeFileProp).exists() -> file(storeFileProp)
                    rootProject.file(storeFileProp).exists() -> rootProject.file(storeFileProp)
                    rootProject.file("app/$storeFileProp").exists() -> rootProject.file("app/$storeFileProp")
                    file("app/$storeFileProp").exists() -> file("app/$storeFileProp")
                    else -> null
                }
                if (resolvedStoreFile != null && resolvedStoreFile.exists()) {
                    keyAlias = keyAliasProp
                    keyPassword = keyPasswordProp
                    storeFile = resolvedStoreFile
                    storePassword = storePasswordProp
                    println("[SigningConfig] Using production release keystore: ${resolvedStoreFile.absolutePath}")
                } else {
                    println("[SigningConfig] WARNING: Keystore file '$storeFileProp' not found. Falling back to debug signing.")
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
