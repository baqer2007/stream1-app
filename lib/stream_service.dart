import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;

class StreamService {
  static const String _firebaseBase = 'https://cee-stream-default-rtdb.firebaseio.com';
  static const String _ceeMediaBase = 'https://cee.buzz/api/android/transcoddedFiles/id/';
  
  static final Random _rng = Random();

  /// ترويسات التخفي المطابقة لمتصفح كروم على الأندرويد
  static Map<String, String> get _stealthHeaders => {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Mobile Safari/537.36',
        'Referer': 'https://cee.buzz/home',
        'Origin': 'https://cee.buzz',
        'Accept': 'application/json, text/plain, */*',
      };

  static void startRelayWorker() {}

  static Future<Map<String, dynamic>?> getVideoSource(String videoId) async {
    if (videoId.isEmpty) return null;

    final cached = await _fetchFromFirebase(videoId);
    if (cached != null) return cached;

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

      for (int i = 0; i < 7; i++) {
        await Future.delayed(const Duration(seconds: 1));
        final result = await _fetchFromFirebase(videoId);
        if (result != null) return result;
      }
    } catch (_) {}
    return null;
  }

  static void preCacheMovieTitles(List<Map<String, String>> items) async {
    for (var item in items) {
      final id = item['id'];
      if (id == null || id.isEmpty) continue;

      final cached = await _fetchFromFirebase(id);
      if (cached == null) {
        await Future.delayed(Duration(milliseconds: 2000 + _rng.nextInt(2000)));
        final fresh = await _fetchFromCeeDirectly(id);
        if (fresh != null) {
          await _saveToFirebase(id, fresh);
        }
      }
    }
  }

  static Future<Map<String, dynamic>?> _fetchFromFirebase(String id) async {
    try {
      final res = await http.get(Uri.parse('$_firebaseBase/videos/$id.json')).timeout(const Duration(seconds: 3));
      if (res.statusCode == 200 && res.body.isNotEmpty && res.body != 'null') {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  static Future<void> _saveToFirebase(String id, Map<String, dynamic> data) async {
    try {
      await http.put(
        Uri.parse('$_firebaseBase/videos/$id.json'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(data),
      );
    } catch (_) {}
  }

  static Future<Map<String, dynamic>?> _fetchFromCeeDirectly(String id) async {
    try {
      final res = await http.get(Uri.parse('$_ceeMediaBase$id'), headers: _stealthHeaders).timeout(const Duration(seconds: 6));

      if (res.statusCode == 200 && res.body.isNotEmpty) {
        dynamic data = jsonDecode(utf8.decode(res.bodyBytes));
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
