import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class StreamService {
  static const String _firebaseBase = 'https://cee-stream-default-rtdb.firebaseio.com';
  static const String _cacheNode = 'stream_cache_v3';

  static Map<String, String> get stealthHeaders => {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Mobile Safari/537.36',
        'Referer': 'https://cee.buzz/home',
        'Origin': 'https://cee.buzz',
      };

  static void startRelayWorker() {}

  static Future<Map<String, dynamic>?> getVideoSource(String videoId) async {
    if (videoId.isEmpty) return null;

    // 1. قراءة الكاش أولاً (يعمل حتى لو الـ VPN مشغل)
    final cached = await _fetchFromFirebase(videoId);
    if (cached != null) return cached;

    // 2. إذا لم يكن محفوظاً، نسحبه مباشرة
    final fresh = await _fetchFromCeeDirectly(videoId);
    if (fresh != null) {
      _saveToFirebase(videoId, fresh);
      return fresh;
    }

    return await _requestFromRelayNetwork(videoId);
  }

  static Future<Map<String, dynamic>?> _requestFromRelayNetwork(String videoId) async {
    try {
      await http.put(
        Uri.parse('$_firebaseBase/pending_requests/$videoId.json'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'t': DateTime.now().millisecondsSinceEpoch}),
      );

      for (int i = 0; i < 6; i++) {
        await Future.delayed(const Duration(seconds: 1));
        final result = await _fetchFromFirebase(videoId);
        if (result != null) return result;
      }
    } catch (_) {}
    return null;
  }

  static Future<Map<String, dynamic>?> _fetchFromFirebase(String id) async {
    try {
      final res = await http.get(Uri.parse('$_firebaseBase/$_cacheNode/$id.json')).timeout(const Duration(seconds: 3));
      if (res.statusCode == 200 && res.body.isNotEmpty && res.body != 'null') {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  static Future<void> _saveToFirebase(String id, Map<String, dynamic> data) async {
    try {
      await http.put(
        Uri.parse('$_firebaseBase/$_cacheNode/$id.json'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(data),
      );
    } catch (_) {}
  }

  static Future<Map<String, dynamic>?> _fetchFromCeeDirectly(String id) async {
    try {
      final res = await http.get(
        Uri.parse('https://cee.buzz/api/android/transcoddedFiles/id/$id'),
        headers: stealthHeaders,
      ).timeout(const Duration(seconds: 6));

      if (res.statusCode == 200 && res.body.isNotEmpty) {
        dynamic data = jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
        List list = (data is List) ? data : (data['videos'] ?? []);
        if (list.isEmpty) return null;

        List<Map<String, String>> qualities = [];
        for (var item in list) {
          final resName = item['resolution']?.toString() ?? 'Auto';
          final url = item['videoUrl']?.toString() ?? item['videourl']?.toString() ?? item['url']?.toString();
          if (url != null && url.isNotEmpty) {
            qualities.add({'resolution': resName, 'url': url});
          }
        }

        if (qualities.isEmpty) return null;

        final defaultUrl = qualities.firstWhere((q) => q['resolution'] == '720p', orElse: () => qualities.first)['url'];

        return {
          'video_url': defaultUrl,
          'qualities': qualities,
        };
      }
    } catch (_) {}
    return null;
  }
}
