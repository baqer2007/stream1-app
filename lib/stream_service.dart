import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class StreamService {
  static const String _firebaseUrl =
      'https://cee-stream-default-rtdb.firebaseio.com';
  static bool _isWorkerActive = false;

  /// تشغيل مستمع المهام الصامت لمعالجة الطلبات القادمة من خارج العراق
  static void startRelayWorker() {
    if (_isWorkerActive) return;
    _isWorkerActive = true;

    Timer.periodic(const Duration(seconds: 4), (timer) async {
      await _processPendingRequests();
    });
  }

  /// الدالة الأساسية لجلب رابط الفيديو والجودات عبر المعرف الحقيقي (nb)
  static Future<Map<String, dynamic>?> getVideoSource(String videoId) async {
    if (videoId.isEmpty) return null;

    // 1. فحص الكاش السحابي في Firebase أولاً (للسرعة القصوى وللعمل خارج العراق)
    final cached = await _fetchFromFirebase(videoId);
    if (cached != null) return cached;

    // 2. المحاولة المباشرة من سيرفر سينمانا الداخلي (يعمل بنجاح للمتواجدين داخل العراق)
    final fresh = await _fetchFromCeeDirectly(videoId);
    if (fresh != null) {
      _saveToFirebase(videoId, fresh);
      return fresh;
    }

    // 3. إذا فشل الجلب وكان المستخدم بالخارج، نرسل طلباً للريلاي في Firebase وننتظر معالجته
    return await _requestFromRelayNetwork(videoId);
  }

  /// إرسال طلب سحب إلى شبكة الريلاي والانتظار حتى يجلب المستخدمون في الداخل الرابط
  static Future<Map<String, dynamic>?> _requestFromRelayNetwork(
      String videoId) async {
    try {
      await http.put(
        Uri.parse('$_firebaseUrl/pending_requests/$videoId.json'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'requestedAt': DateTime.now().millisecondsSinceEpoch,
        }),
      );

      // مراقبة النتيجة كل ثانية لمدة 8 ثوانٍ
      for (int i = 0; i < 8; i++) {
        await Future.delayed(const Duration(seconds: 1));
        final result = await _fetchFromFirebase(videoId);
        if (result != null) return result;
      }
    } catch (_) {}
    return null;
  }

  /// معالجة الطلبات المعلقة في Firebase بواسطة المستخدمين المتواجدين داخل العراق
  static Future<void> _processPendingRequests() async {
    try {
      final res = await http
          .get(Uri.parse('$_firebaseUrl/pending_requests.json'))
          .timeout(const Duration(seconds: 4));

      if (res.statusCode == 200 && res.body != 'null') {
        final dynamic decoded = jsonDecode(res.body);
        if (decoded is Map<String, dynamic>) {
          for (var videoId in decoded.keys) {
            final data = await _fetchFromCeeDirectly(videoId);
            if (data != null) {
              await _saveToFirebase(videoId, data);
              await http.delete(
                  Uri.parse('$_firebaseUrl/pending_requests/$videoId.json'));
              break; // معالجة عنصر واحد في كل دورة لعدم الضغط على الاتصال
            }
          }
        }
      }
    } catch (_) {}
  }

  /// سحب استباقي للأفلام والمسلسلات وتخزينها سحابياً لمن هم بالخارج
  static void preCacheMovieTitles(List<Map<String, String>> items) async {
    for (var item in items) {
      final id = item['id'];
      if (id == null || id.isEmpty) continue;

      final cached = await _fetchFromFirebase(id);
      if (cached == null) {
        final fresh = await _fetchFromCeeDirectly(id);
        if (fresh != null) {
          await _saveToFirebase(id, fresh);
        }
      }
    }
  }

  /// استرجاع البيانات المخزنة من Firebase
  static Future<Map<String, dynamic>?> _fetchFromFirebase(String id) async {
    try {
      final res = await http
          .get(Uri.parse('$_firebaseUrl/videos/$id.json'))
          .timeout(const Duration(seconds: 4));
      if (res.statusCode == 200 && res.body.isNotEmpty && res.body != 'null') {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  /// حفظ الرابط والجودات في Firebase
  static Future<void> _saveToFirebase(
      String id, Map<String, dynamic> data) async {
    try {
      await http.put(
        Uri.parse('$_firebaseUrl/videos/$id.json'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(data),
      );
    } catch (_) {}
  }

  /// استخراج الجودات وروابط الفيديو من API سينمانا الحقيقي (transcoddedFiles)
  static Future<Map<String, dynamic>?> _fetchFromCeeDirectly(String id) async {
    try {
      final res = await http.get(
        Uri.parse('https://cee.buzz/api/android/transcoddedFiles/id/$id'),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Linux; Android 10; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36',
          'Referer': 'https://cee.buzz/home',
          'Accept': 'application/json, text/plain, */*',
        },
      ).timeout(const Duration(seconds: 6));

      if (res.statusCode == 200 && res.body.isNotEmpty) {
        dynamic data = jsonDecode(utf8.decode(res.bodyBytes));
        List list = (data is List) ? data : (data['videos'] ?? []);
        if (list.isEmpty) return null;

        List<Map<String, String>> qualities = [];
        for (var item in list) {
          final resName = item['resolution']?.toString() ?? 'Auto';
          final url = item['videoUrl']?.toString() ??
              item['videourl']?.toString() ??
              item['url']?.toString();
          if (url != null && url.isNotEmpty) {
            qualities.add({'resolution': resName, 'url': url});
          }
        }

        if (qualities.isEmpty) return null;

        // اختيار دقة 720p افتراضياً، أو أول دقة متوفرة
        final defaultUrl = qualities.firstWhere(
          (q) => q['resolution'] == '720p',
          orElse: () => qualities.first,
        )['url'];

        return {
          'video_url': defaultUrl,
          'qualities': qualities,
        };
      }
    } catch (_) {}
    return null;
  }
}
