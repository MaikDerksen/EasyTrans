# ML Kit wires its translator internals through component registrars; R8 full mode (AGP 9
# default) otherwise optimizes their fields away and translation fails with an NPE in
# TranslatorImpl$Factory.
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_translate.** { *; }
-keep class com.google.android.gms.internal.mlkit_common.** { *; }
-keep class com.google.firebase.components.** { *; }
