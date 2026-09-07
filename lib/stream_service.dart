import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class StreamService {
  static const String _firebaseBase =
      'https://cee-stream-default-rtdb.firebaseio.com';
  static const String _cacheNode = 'stream_cache_v4';

  static Map<String, String> get stealthHeaders => {
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Mobile Safari/537.36',
        'Referer': 'https://cee.buzz/home',
        'Origin': 'https://cee.buzz',
        'Accept': 'application/json, text/plain, */*',
      };

  static Timer? _relayListener;
  static bool _isWorkerRunning = false;

  /// تفعيل خادم الترحيل التلقائي (يعمل في خلفية التطبيق لمن هم داخل العراق)
  static void startRelayWorker() {
    if (_isWorkerRunning) return;
    _isWorkerRunning = true;

    // فحص كل 3 ثوانٍ إذا كانت هناك طلبات معلقة من أشخاص بالخارج
    _relayListener = Timer.periodic(const Duration(seconds: 3), (_) async {
      try {
        final res = await http
            .get(Uri.parse('$_firebaseBase/pending_requests.json'))
            .timeout(const Duration(seconds: 4));

        if (res.statusCode == 200 && res.body.isNotEmpty && res.body != 'null') {
          final Map<String, dynamic> requests = jsonDecode(res.body);

          for (String videoId in requests.keys) {
            // جلب الرابط بالـ IP المحلي العراقي وتخزينه فوراً للمستخدم الخارجي
            final fresh = await _fetchFromCeeDirectly(videoId);
            if (fresh != null) {
              await _saveToFirebase(videoId, fresh);
            }
            // حذف الطلب المكتمل حتى لا يتكرر
            await http.delete(Uri.parse('$_firebaseBase/pending_requests/$videoId.json'));
          }
        }
      } catch (_) {}
    });
  }

  static void stopRelayWorker() {
    _relayListener?.cancel();
    _isWorkerRunning = false;
  }

  /// إرسال نبضات النشاط للإحصائيات الحقيقية
  static Future<void> sendHeartbeat(String userId, {String city = 'بغداد', String genre = 'عام'}) async {
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      await http.put(
        Uri.parse('$_firebaseBase/live_stats/active_sessions/$userId.json'),
        body: jsonEncode({
          'last_active': now,
          'city': city,
          'genre': genre,
        }),
      );
    } catch (_) {}
  }

  /// تسجيل حدث مشاهدة حقيقي
  static Future<void> recordWatchEvent(String mediaId, String title, {String genre = 'دراما'}) async {
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final viewsRes = await http.get(Uri.parse('$_firebaseBase/live_stats/total_views.json'));
      int count = 0;
      if (viewsRes.statusCode == 200 && viewsRes.body != 'null') {
        count = int.tryParse(viewsRes.body) ?? 0;
      }
      count++;
      await http.put(
        Uri.parse('$_firebaseBase/live_stats/total_views.json'),
        body: jsonEncode(count),
      );

      await http.post(
        Uri.parse('$_firebaseBase/live_stats/recent_views.json'),
        body: jsonEncode({
          'media_id': mediaId,
          'title': title,
          'genre': genre,
          'timestamp': now,
        }),
      );
    } catch (_) {}
  }

  /// جلب الإحصائيات الحقيقية
  static Future<Map<String, dynamic>> getRealAdminStats() async {
    int activeUsers = 0;
    int totalViews = 0;
    List<Map<String, dynamic>> recentPlays = [];
    Map<String, int> heatmapCities = {'بغداد': 0, 'البصرة': 0, 'أربيل': 0, 'النجف': 0, 'الموصل': 0};
    Map<String, int> genreBreakdown = {'أنمي': 0, 'أكشن': 0, 'دراما': 0, 'رعب': 0};

    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final sessionsRes = await http.get(Uri.parse('$_firebaseBase/live_stats/active_sessions.json')).timeout(const Duration(seconds: 4));
      if (sessionsRes.statusCode == 200 && sessionsRes.body != 'null') {
        final Map<String, dynamic> data = jsonDecode(sessionsRes.body);
        data.forEach((k, v) {
          final last = v['last_active'] as int? ?? 0;
          if (now - last <= 600000) {
            activeUsers++;
            final c = v['city']?.toString() ?? 'بغداد';
            heatmapCities[c] = (heatmapCities[c] ?? 0) + 1;
            final g = v['genre']?.toString() ?? 'أنمي';
            genreBreakdown[g] = (genreBreakdown[g] ?? 0) + 1;
          }
        });
      }

      final viewsRes = await http.get(Uri.parse('$_firebaseBase/live_stats/total_views.json')).timeout(const Duration(seconds: 4));
      if (viewsRes.statusCode == 200 && viewsRes.body != 'null') {
        totalViews = int.tryParse(viewsRes.body) ?? 0;
      }

      final recRes = await http.get(Uri.parse('$_firebaseBase/live_stats/recent_views.json?orderBy="\$key"&limitToLast=10')).timeout(const Duration(seconds: 4));
      if (recRes.statusCode == 200 && recRes.body != 'null') {
        final Map<String, dynamic> rData = jsonDecode(recRes.body);
        rData.forEach((k, v) {
          recentPlays.add({
            'title': v['title'] ?? 'محتوى مجهول',
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
      'genre_breakdown': genreBreakdown,
    };
  }

  /// طلب مصدر الفيديو (كاش -> مباشر محلي -> طلب من مستخدم عراقي P2P Relay)
  static Future<Map<String, dynamic>?> getVideoSource(String videoId) async {
    if (videoId.isEmpty) return null;

    // 1. فحص الكاش السحابي المشترك أولاً
    final cached = await _fetchFromFirebase(videoId);
    if (cached != null) return cached;

    // 2. إذا لم يكن في الكاش، نحاول الطلب المباشر (ينجح إذا كان المستخدم داخل العراق)
    final fresh = await _fetchFromCeeDirectly(videoId);
    if (fresh != null) {
      _saveToFirebase(videoId, fresh);
      return fresh;
    }

    // 3. إذا فشل الطلب المباشر (المستخدم بالخارج أو مشغل VPN):
    // نقوم بتسجيل طلب في Firebase لتقوم الأجهزة داخل العراق بجلبه بدلاً عنه!
    return await _requestFromLocalPeers(videoId);
  }

  /// إرسال التذكرة للأجهزة العراقية وانتظار جلب الرابط
  static Future<Map<String, dynamic>?> _requestFromLocalPeers(String videoId) async {
    try {
      await http.put(
        Uri.parse('$_firebaseBase/pending_requests/$videoId.json'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'requested_at': DateTime.now().millisecondsSinceEpoch}),
      );

      // انتظار استجابة أحد الأجهزة العراقية في الكاش لمدة تصل إلى 6 ثوانٍ
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
        return {
          'video_url': autoUrl,
          'qualities': qualities,
        };
      }
    } catch (_) {}
    return null;
  }
}
