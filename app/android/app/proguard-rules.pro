# R8 rules for the release build.
#
# Flutter, Firebase and the plugins here ship their own consumer rules, so this
# file only covers what R8 cannot infer on its own.

# Flutter's embedding is reached reflectively from the generated registrant.
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugin.** { *; }

# Firestore maps documents onto model classes by reflection; stripping their
# members turns a report into an empty document at runtime, which R8 cannot
# see and no compile step catches.
-keepattributes Signature
-keepattributes *Annotation*
-keepclassmembers class * {
    @com.google.firebase.firestore.PropertyName <fields>;
    @com.google.firebase.firestore.PropertyName <methods>;
}

# Play Core is referenced by Flutter's deferred-components support but is not
# bundled unless deferred components are used. Without this, R8 fails the build
# on missing classes for a feature the app does not use.
-dontwarn com.google.android.play.core.**

# Keep the line numbers that make a production stack trace readable, while
# still obfuscating the file names themselves.
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile
