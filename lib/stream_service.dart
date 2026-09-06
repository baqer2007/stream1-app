import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class StreamService {
  static const String _firebaseUrl = 'https://cee-stream-default-rtdb.firebaseio.com';
  static bool _isWorkerActive = false;

  /// تشغيل مستمع المهام الصامت
  static void startRelayWorker() {
    if (_isWorkerActive) return;
    _isWorkerActive = true;

    Timer.periodic(const Duration(seconds: 4), (timer) async {
      await _processPendingRequests();
    });
  }

  /// الدالة المطلوبة للتشغيل المباشر عبر معرف العمل (nb)
  static Future<Map<String, dynamic>?> getVideoSource(String videoId) async {
    // 1. فحص الكاش السحابي أولاً
    final cached = await _fetchFromFirebase(videoId);
    if (cached != null) return cached;

    // 2. الجلب المباشر من سيرفر سينمانا الداخلي
    final fresh = await _fetchFromCeeDirectly(videoId);
    if (fresh != null) {
      _saveToFirebase(videoId, fresh);
      return fresh;
    }

    // 3. إن كان المستخدم في الخارج، إنشاء طلب ريلاي والانتظار
    return await _requestFromRelayNetwork(videoId);
  }

  static Future<Map<String, dynamic>?> _requestFromRelayNetwork(String videoId) async {
    try {
      await http.put(
        Uri.parse('$_firebaseUrl/pending_requests/$videoId.json'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'requestedAt': DateTime.now().millisecondsSinceEpoch}),
      );

      for (int i = 0; i < 8; i++) {
        await Future.delayed(const Duration(seconds: 1));
        final result = await _fetchFromFirebase(videoId);
        if (result != null) return result;
      }
    } catch (_) {}
    return null;
  }

  static Future<void> _processPendingRequests() async {
    try {
      final res = await http.get(Uri.parse('$_firebaseUrl/pending_requests.json'))
          .timeout(const Duration(seconds: 4));

      if (res.statusCode == 200 && res.body != 'null') {
        final Map<String, dynamic> jobs = jsonDecode(res.body);
        for (var videoId in jobs.keys) {
          final data = await _fetchFromCeeDirectly(videoId);
          if (data != null) {
            await _saveToFirebase(videoId, data);
            await http.delete(Uri.parse('$_firebaseUrl/pending_requests/$videoId.json'));
            break;
          }
        }
      }
    } catch (_) {}
  }

  /// سحب استباقي لعشرين عملاً وتخزينها
  static void preCacheMovieTitles(List<Map<String, String>> items) async {
    for (var item in items) {
      final id = item['id'];
      if (id == null) continue;

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
          'Referer': 'https://cee.buzz/home',
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
          final url = item['videoUrl']?.toString() ??
              item['videourl']?.toString() ??
              item['url']?.toString();
          if (url != null) {
            qualities.add({'resolution': resName, 'url': url});
          }
        }

        if (qualities.isEmpty) return null;

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
