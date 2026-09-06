import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class StreamService {
  static const String _firebaseUrl = 'https://cee-stream-default-rtdb.firebaseio.com';
  static bool _isWorkerActive = false;

  /// 1. تشغيل عامل المعالجة في الخلفية للمستخدم العراقي
  static void startRelayWorker() {
    if (_isWorkerActive) return;
    _isWorkerActive = true;

    // فحص طلبات المستخدمين المعلقة كل 3 ثوانٍ
    Timer.periodic(const Duration(seconds: 3), (timer) async {
      await _processPendingRequests();
    });
  }

  /// 2. الدالة الرئيسية لطلب وتشغيل الفيديو
  static Future<Map<String, dynamic>?> getVideoSource(String videoId) async {
    // أ. البحث أولاً في الكاش المحفوظ
    final cached = await _fetchFromFirebase(videoId);
    if (cached != null) return cached;

    // ب. محاولة الجلب المباشر (إذا كان الجهاز في العراق)
    final direct = await _fetchFromCeeDirectly(videoId);
    if (direct != null) {
      await _saveToFirebase(videoId, direct);
      return direct;
    }

    // ج. إذا كان المستخدم في الخارج ولم يجد الفيديو، يرسل طلب مهمة للمستخدمين في العراق
    return await _requestFromRelayNetwork(videoId);
  }

  /// إرسال طلب للمستخدمين داخل العراق والانتظار حتى جلبه
  static Future<Map<String, dynamic>?> _requestFromRelayNetwork(String videoId) async {
    try {
      // كتابة الطلب في قائمة الانتظار
      await http.put(
        Uri.parse('$_firebaseUrl/pending_requests/$videoId.json'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'requestedAt': DateTime.now().millisecondsSinceEpoch}),
      );

      // الانتظار مع فحص النتيجة كل ثانية لمدة أقصاها 10 ثوانٍ
      for (int i = 0; i < 10; i++) {
        await Future.delayed(const Duration(seconds: 1));
        final result = await _fetchFromFirebase(videoId);
        if (result != null) return result;
      }
    } catch (_) {}
    return null;
  }

  /// معالجة المهام المعلقة (تعمل فقط لدى مستخدمي العراق القادرين على فتح الرابط)
  static Future<void> _processPendingRequests() async {
    try {
      final res = await http.get(Uri.parse('$_firebaseUrl/pending_requests.json'))
          .timeout(const Duration(seconds: 3));

      if (res.statusCode == 200 && res.body != 'null') {
        final Map<String, dynamic> jobs = jsonDecode(res.body);
        for (var videoId in jobs.keys) {
          final data = await _fetchFromCeeDirectly(videoId);
          if (data != null) {
            await _saveToFirebase(videoId, data);
            // حذف الطلب بعد اكتماله
            await http.delete(Uri.parse('$_firebaseUrl/pending_requests/$videoId.json'));
            break; // معالجة عنصر واحد في كل دورة لعدم استهلاك الموارد
          }
        }
      }
    } catch (_) {}
  }

  /// الجلب الاستباقي لقائمة من المعرفات عند فتح التطبيق
  static void preCacheMovieIds(List<String> ids) async {
    for (var id in ids) {
      final cached = await _fetchFromFirebase(id);
      if (cached == null) {
        final fresh = await _fetchFromCeeDirectly(id);
        if (fresh != null) {
          await _saveToFirebase(id, fresh);
        }
      }
    }
  }

  static Future<Map<String, dynamic>?> _fetchFromFirebase(String id) async {
    try {
      final res = await http.get(Uri.parse('$_firebaseUrl/videos/$id.json'))
          .timeout(const Duration(seconds: 4));
      if (res.statusCode == 200 && res.body != 'null') {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  static Future<void> _saveToFirebase(String id, Map<String, dynamic> data) async {
    try {
      await http.put(
        Uri.parse('$_firebaseUrl/videos/$id.json'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(data),
      );
    } catch (_) {}
  }

  static Future<Map<String, dynamic>?> _fetchFromCeeDirectly(String id) async {
    try {
      final res = await http.get(
        Uri.parse('https://cee.buzz/api/android/transcoddedFiles/id/$id'),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Linux; Android 10; Mobile) AppleWebKit/537.36',
          'Referer': 'https://cee.buzz/',
          'Accept': 'application/json, text/plain, */*',
        },
      ).timeout(const Duration(seconds: 6));

      if (res.statusCode == 200) {
        dynamic data = jsonDecode(res.body);
        List list = (data is List) ? data : (data['videos'] ?? []);
        if (list.isEmpty) return null;

        List<Map<String, String>> qualities = [];
        for (var item in list) {
          final resName = item['resolution']?.toString() ?? 'Auto';
          final url = item['videoUrl']?.toString() ?? item['videourl']?.toString() ?? item['url']?.toString();
          if (url != null) qualities.add({'resolution': resName, 'url': url});
        }

        if (qualities.isEmpty) return null;

        final defaultUrl = qualities.firstWhere(
          (q) => q['resolution'] == '720p',
          orElse: () => qualities.first,
        )['url'];

        return {'video_url': defaultUrl, 'qualities': qualities};
      }
    } catch (_) {}
    return null;
  }
}
