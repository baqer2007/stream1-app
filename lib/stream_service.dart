import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class StreamService {
  static const String _firebaseUrl = 'https://cee-stream-default-rtdb.firebaseio.com';
  static bool _isWorkerActive = false;

  static void startRelayWorker() {
    if (_isWorkerActive) return;
    _isWorkerActive = true;

    Timer.periodic(const Duration(seconds: 3), (timer) async {
      await _processPendingRequests();
    });
  }

  /// البحث التلقائي بالاسم لاستخراج المعرف الحقيقي من cee.buzz
  static Future<String?> searchCeeId(String title, {bool isTv = false, int season = 1, int episode = 1}) async {
    try {
      final cleanTitle = Uri.encodeComponent(title.trim());
      final searchUrl = Uri.parse('https://cee.buzz/api/android/allVideo/page/1/level/0?title=$cleanTitle');

      final res = await http.get(
        searchUrl,
        headers: {
          'User-Agent': 'Mozilla/5.0 (Linux; Android 10; Mobile) AppleWebKit/537.36',
          'Referer': 'https://cee.buzz/',
        },
      ).timeout(const Duration(seconds: 6));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final List list = (data is List) ? data : (data['articles'] ?? data['data'] ?? []);
        if (list.isEmpty) return null;

        // مطابقة العمل الأول
        final firstMatch = list.first;
        final rootId = firstMatch['id']?.toString();
        if (rootId == null) return null;

        if (!isTv) {
          return rootId; // للأفلام: المعرف مباشر
        }

        // للمسلسلات: جلب الحلقات الخاصة بالموسم
        final seasonsUrl = Uri.parse('https://cee.buzz/api/android/allVideo/page/1/level/2/sub_id/$rootId');
        final sRes = await http.get(seasonsUrl, headers: {'User-Agent': 'Mozilla/5.0'}).timeout(const Duration(seconds: 6));
        if (sRes.statusCode == 200) {
          final sData = jsonDecode(sRes.body);
          final List epList = (sData is List) ? sData : (sData['articles'] ?? []);

          // البحث عن الحلقة المطابقة
          for (var ep in epList) {
            final epTitle = ep['title']?.toString() ?? '';
            final epNum = ep['episode']?.toString() ?? '';
            final sNum = ep['season']?.toString() ?? '1';

            if (sNum == season.toString() && (epNum == episode.toString() || epTitle.contains('$episode'))) {
              return ep['id']?.toString();
            }
          }
          if (epList.isNotEmpty) return epList.first['id']?.toString();
        }
        return rootId;
      }
    } catch (_) {}
    return null;
  }

  /// الجلب الذكي: يبحث في الكاش أولاً، وإن لم يجده يطلبه بالاسم الفعلي
  static Future<Map<String, dynamic>?> getVideoSourceByTitle({
    required String title,
    required String tmdbId,
    bool isTv = false,
    int season = 1,
    int episode = 1,
  }) async {
    final cacheKey = isTv ? '${tmdbId}_s${season}_e$episode' : tmdbId;

    // 1. الكاش أولاً
    final cached = await _fetchFromFirebase(cacheKey);
    if (cached != null) return cached;

    // 2. البحث عن معرف سينمانا الحقيقي في الداخل
    final ceeId = await searchCeeId(title, isTv: isTv, season: season, episode: episode);
    if (ceeId != null) {
      final freshData = await _fetchFromCeeDirectly(ceeId);
      if (freshData != null) {
        await _saveToFirebase(cacheKey, freshData);
        return freshData;
      }
    }

    // 3. إن كان المستخدم بالخارج ولم يعثر عليه، إرسال مهمة للريلاي
    return await _requestFromRelayNetwork(cacheKey, title);
  }

  static Future<Map<String, dynamic>?> _requestFromRelayNetwork(String key, String title) async {
    try {
      await http.put(
        Uri.parse('$_firebaseUrl/pending_requests/$key.json'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'title': title,
          'requestedAt': DateTime.now().millisecondsSinceEpoch,
        }),
      );

      for (int i = 0; i < 8; i++) {
        await Future.delayed(const Duration(seconds: 1));
        final result = await _fetchFromFirebase(key);
        if (result != null) return result;
      }
    } catch (_) {}
    return null;
  }

  static Future<void> _processPendingRequests() async {
    try {
      final res = await http.get(Uri.parse('$_firebaseUrl/pending_requests.json'))
          .timeout(const Duration(seconds: 3));

      if (res.statusCode == 200 && res.body != 'null') {
        final Map<String, dynamic> jobs = jsonDecode(res.body);
        for (var key in jobs.keys) {
          final job = jobs[key];
          final title = job['title']?.toString() ?? '';
          if (title.isNotEmpty) {
            final ceeId = await searchCeeId(title);
            if (ceeId != null) {
              final data = await _fetchFromCeeDirectly(ceeId);
              if (data != null) {
                await _saveToFirebase(key, data);
                await http.delete(Uri.parse('$_firebaseUrl/pending_requests/$key.json'));
                break;
              }
            }
          }
        }
      }
    } catch (_) {}
  }

  static void preCacheMovieTitles(List<Map<String, String>> items) async {
    for (var item in items) {
      final id = item['id']!;
      final title = item['title']!;
      final cached = await _fetchFromFirebase(id);
      if (cached == null) {
        final ceeId = await searchCeeId(title);
        if (ceeId != null) {
          final fresh = await _fetchFromCeeDirectly(ceeId);
          if (fresh != null) {
            await _saveToFirebase(id, fresh);
          }
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
