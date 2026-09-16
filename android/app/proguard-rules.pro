# تجريد جميع رسائل الـ Log والـ Print من حزمة الـ Release
-assumenosideeffects class android.util.Log {
    public static *** d(...);
    public static *** v(...);
    public static *** i(...);
}

# تشويش أسماء الدوال والحزم
-repackageclasses ''
-allowaccessmodification

# الحفاظ على مكونات Flutter و Firebase الأساسية
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class com.google.firebase.** { *; }
