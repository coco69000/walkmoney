# Règles de désobscurcissement et de conservation R8 / ProGuard pour Flutter et les plugins

# Flutter
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Google Navigation & Maps
-keep class com.google.android.libraries.navigation.** { *; }
-keep class com.google.android.apps.gmm.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.android.libraries.navigation.**
-dontwarn com.google.android.gms.**

# MapLibre
-keep class org.maplibre.android.** { *; }
-dontwarn org.maplibre.android.**

# Stripe
-keep class com.stripe.android.** { *; }
-dontwarn com.stripe.android.**

# RevenueCat / Purchases
-keep class com.revenuecat.purchases.** { *; }
-dontwarn com.revenuecat.purchases.**

# Firebase
-dontwarn com.google.firebase.**
-keep class com.google.firebase.** { *; }

# Réseau & Serialisation
-dontwarn okhttp3.**
-dontwarn okio.**
-dontwarn javax.annotation.**
-dontwarn org.conscrypt.**
