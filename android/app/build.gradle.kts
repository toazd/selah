import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

java {
    toolchain {
        languageVersion.set(JavaLanguageVersion.of(25))
    }
}

android {
    namespace = "com.selah.holybible"
    compileSdk = 37

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_25
        targetCompatibility = JavaVersion.VERSION_25
    }


    signingConfigs {
        create("release") {
            storeFile = file("selah-release.keystore")
            storePassword = "2Samuel22:33"
            keyAlias = "selah-key"
            keyPassword = "2Samuel22:33"
        }
    }

    defaultConfig {
        applicationId = "com.selah.holybible"
        minSdk = 27
        targetSdk = 35
        minSdk = flutter.minSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = false
            signingConfig = signingConfigs.getByName("release")
        }

        debug {
            isMinifyEnabled = false
            isShrinkResources = false
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        // Explicit bytecode target; keeps parity with compileOptions above.
        // (Optional in practice — with the Java 25 toolchain set, Kotlin
        //  defaults to it — but keeping it explicit documents intent.)
        jvmTarget = JvmTarget.JVM_25

        freeCompilerArgs.add("-Xlint:deprecation")
    }
}

flutter {
    source = "../.."
}
