import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class StreamService {
  static const String _firebaseBase = 'https://cee-stream-default-rtdb.firebaseio.com';
  static const String _cacheNode = 'stream_cache_v4';

  static Map<String, String> get stealthHeaders => {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Mobile Safari/537.36',
        'Referer': 'https://cee.buzz/home',
        'Origin': 'https://cee.buzz',
        'Accept': 'application/json, text/plain, */*',
      };

  static Timer? _relayWorkerTimer;
  static bool _workerRunning = false;

  static void startRelayWorker() {
    if (_workerRunning) return;
    _workerRunning = true;

    _relayWorkerTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      try {
        final res = await http.get(Uri.parse('$_firebaseBase/pending_requests.json')).timeout(const Duration(seconds: 4));
        if (res.statusCode == 200 && res.body.isNotEmpty && res.body != 'null') {
          final Map<String, dynamic> requests = jsonDecode(res.body);
          for (var entry in requests.entries) {
            final String videoId = entry.key;
            final freshData = await _fetchFromCeeDirectly(videoId);
            if (freshData != null) {
              await _saveToFirebase(videoId, freshData);
            }
            await http.delete(Uri.parse('$_firebaseBase/pending_requests/$videoId.json'));
          }
        }
      } catch (_) {}
    });
  }

  static void stopRelayWorker() {
    _relayWorkerTimer?.cancel();
    _workerRunning = false;
  }

  static Future<void> sendHeartbeat(String userId, {String city = 'العراق', String genre = 'عام'}) async {
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      await http.put(
        Uri.parse('$_firebaseBase/live_stats/active_sessions/$userId.json'),
        body: jsonEncode({'last_active': now, 'city': city, 'genre': genre}),
      );
    } catch (_) {}
  }

  static Future<void> recordWatchEvent(String mediaId, String title, {String genre = 'عام'}) async {
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final viewsRes = await http.get(Uri.parse('$_firebaseBase/live_stats/total_views.json'));
      int count = (viewsRes.statusCode == 200 && viewsRes.body != 'null') ? (int.tryParse(viewsRes.body) ?? 0) : 0;
      count++;
      await http.put(Uri.parse('$_firebaseBase/live_stats/total_views.json'), body: jsonEncode(count));

      await http.post(
        Uri.parse('$_firebaseBase/live_stats/recent_views.json'),
        body: jsonEncode({'media_id': mediaId, 'title': title, 'genre': genre, 'timestamp': now}),
      );
    } catch (_) {}
  }

  static Future<Map<String, dynamic>> getRealAdminStats() async {
    int activeUsers = 0;
    int totalViews = 0;
    List<Map<String, dynamic>> recentPlays = [];
    Map<String, int> heatmapCities = {'بغداد': 0, 'البصرة': 0, 'أربيل': 0, 'النجف': 0};

    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final sRes = await http.get(Uri.parse('$_firebaseBase/live_stats/active_sessions.json')).timeout(const Duration(seconds: 4));
      if (sRes.statusCode == 200 && sRes.body != 'null') {
        final Map<String, dynamic> data = jsonDecode(sRes.body);
        data.forEach((k, v) {
          final last = v['last_active'] as int? ?? 0;
          if (now - last <= 600000) {
            activeUsers++;
            final c = v['city']?.toString() ?? 'بغداد';
            heatmapCities[c] = (heatmapCities[c] ?? 0) + 1;
          }
        });
      }

      final vRes = await http.get(Uri.parse('$_firebaseBase/live_stats/total_views.json')).timeout(const Duration(seconds: 4));
      if (vRes.statusCode == 200 && vRes.body != 'null') {
        totalViews = int.tryParse(vRes.body) ?? 0;
      }

      final rRes = await http.get(Uri.parse('$_firebaseBase/live_stats/recent_views.json?orderBy="\$key"&limitToLast=8')).timeout(const Duration(seconds: 4));
      if (rRes.statusCode == 200 && rRes.body != 'null') {
        final Map<String, dynamic> rData = jsonDecode(rRes.body);
        rData.forEach((k, v) {
          recentPlays.add({
            'title': v['title'] ?? '',
            'time': DateTime.fromMillisecondsSinceEpoch(v['timestamp'] ?? now).toLocal().toString().substring(11, 16),
          });
        });
        recentPlays = recentPlays.reversed.toList();
      }
    } catch (_) {}

    return {
      'active_users': activeUsers == 0 ? 1 : activeUsers,
      'total_views': totalViews,
      'recent_plays': recentPlays,
      'heatmap': heatmapCities,
    };
  }

  /// جلب الفيديو المباشر من سينمانا أو الكاش السحابي
  static Future<Map<String, dynamic>?> getVideoSource(String videoId) async {
    if (videoId.isEmpty) return null;

    final cached = await _fetchFromFirebase(videoId);
    if (cached != null) return cached;

    final fresh = await _fetchFromCeeDirectly(videoId);
    if (fresh != null) {
      await _saveToFirebase(videoId, fresh);
      return fresh;
    }

    return await requestRelayedStream(videoId);
  }

  static Future<Map<String, dynamic>?> requestRelayedStream(String videoId) async {
    try {
      await http.put(
        Uri.parse('$_firebaseBase/pending_requests/$videoId.json'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'ts': DateTime.now().millisecondsSinceEpoch}),
      );

      for (int i = 0; i < 6; i++) {
        await Future.delayed(const Duration(seconds: 1));
        final resolved = await _fetchFromFirebase(videoId);
        if (resolved != null) return resolved;
      }
    } catch (_) {}
    return null;
  }

  static Future<Map<String, dynamic>?> _fetchFromFirebase(String id) async {
    try {
      final res = await http.get(Uri.parse('$_firebaseBase/$_cacheNode/$id.json')).timeout(const Duration(seconds: 2));
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
      ).timeout(const Duration(seconds: 4));

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

        final autoUrl = qualities.firstWhere((q) => q['resolution'] == '720p', orElse: () => qualities.first)['url'];
        return {'video_url': autoUrl, 'qualities': qualities};
      }
    } catch (_) {}
    return null;
  }
}
