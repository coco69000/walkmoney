plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // Le plugin Flutter doit être appliqué après Android et Kotlin.
    id("dev.flutter.flutter-gradle-plugin")
}

// Correction du conflit de classes entre Google Maps et Google Navigation
configurations.all {
    exclude(group = "com.google.android.gms", module = "play-services-maps")
}

android {
    namespace = "com.parrel.walkmoney"

    // Google Navigation nécessite souvent un compileSdk récent (34 ou 35)
    compileSdk = flutter.compileSdkVersion

    ndkVersion = "28.1.13356709"

    compileOptions {
        // ACTIVATION INDISPENSABLE pour Google Navigation
        isCoreLibraryDesugaringEnabled = true

        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.parrel.walkmoney"

        // Requis pour Google Navigation (minimum SDK 23)
        // Vérifie dans ton pubspec.yaml que flutter.minSdkVersion est bien >= 23
        minSdk = 24

        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            isShrinkResources = false

            signingConfig = signingConfigs.getByName("debug")

            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Cette dépendance permet d'utiliser Java 8+ sur les versions d'Android plus anciennes
    // Requis par com.google.android.libraries.navigation:navigation:7.3.0
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}
