# Flutter
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }
-keep class io.flutter.embedding.** { *; }

# Play Store deferred components are optional (not used by this app)
-dontwarn com.google.android.play.core.**

# Dio HTTP client
-keep class com.squareup.okhttp3.** { *; }
-keep class okio.** { *; }
-dontwarn com.squareup.okhttp3.**
-dontwarn okio.**

# sqflite
-keep class com.tekartik.sqflite.** { *; }

# path_provider
-keep class io.flutter.plugins.pathprovider.** { *; }

# url_launcher
-keep class io.flutter.plugins.urllauncher.** { *; }

# Keep model classes used for JSON serialization
-keep class dev.pixel.pixel.models.** { *; }
-keepclassmembers class dev.pixel.pixel.models.** { *; }

# Remove debug logging in release
-assumenosideeffects class android.util.Log {
    public static int v(...);
    public static int d(...);
    public static int i(...);
}

# General Android
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile
