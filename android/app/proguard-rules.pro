# حماية بنية Flutter الأساسية ومنع تشويه مكونات التشغيل
-keepattributes *Annotation*
-keepattributes SourceFile,LineNumberTable
-keep public class * extends io.flutter.embedding.android.FlutterActivity
-keep class io.flutter.plugin.** { *; }

# استثناء مكتبات التحميل والخلفية لتعمل دون توقف
-keep class vn.hunghd.flutterdownloader.** { *; }
-keep class androidx.work.** { *; }
-keep class io.flutter.plugins.firebase.** { *; }
-dontwarn com.google.firebase.**
