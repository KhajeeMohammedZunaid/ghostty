# Flutter ProGuard Rules for Ghostty

# Keep Flutter classes
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# Keep local_auth for biometric authentication
-keep class androidx.biometric.** { *; }

# Keep flutter_local_notifications
-keep class com.dexterous.** { *; }

# Keep permission_handler
-keep class com.baseflow.permissionhandler.** { *; }

# Keep home_widget
-keep class es.antonborri.home_widget.** { *; }

# Prevent R8 from removing needed classes
-dontwarn io.flutter.embedding.**
-dontwarn android.**
-dontwarn androidx.**

# Aggressive optimization
-optimizationpasses 7
-dontusemixedcaseclassnames
-verbose
-allowaccessmodification
-repackageclasses ''

# Remove logging in release
-assumenosideeffects class android.util.Log {
    public static *** d(...);
    public static *** v(...);
    public static *** i(...);
    public static *** w(...);
}

# Remove debug code
-assumenosideeffects class java.io.PrintStream {
    public void println(...);
    public void print(...);
}
