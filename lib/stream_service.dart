import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;

class StreamService {
  static const String _firebaseUrl =
      'https://cee-stream-default-rtdb.firebaseio.com';
  static bool _isWorkerActive = false;
  static final Random _rng = Random();

  /// الترويسات الرسمية المطابقة لمتصفح Chrome على هاتف Android حديث
  static Map<String, String> get _stealthHeaders => {
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 14; Mobile; rv:128.0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Mobile Safari/537.36',
        'Referer': 'https://cee.buzz/home',
        'Origin': 'https://cee.buzz',
        'Accept': 'application/json, text/plain, */*',
        'Accept-Language': 'ar,en-US;q=0.9,en;q=0.8',
        'sec-ch-ua': '"Not;A=Brand";v="99", "Chromium";v="139"',
        'sec-ch-ua-mobile': '?1',
        'sec-ch-ua-platform': '"Android"',
        'Sec-Fetch-Dest': 'empty',
        'Sec-Fetch-Mode': 'cors',
        'Sec-Fetch-Site': 'same-origin',
      };

  /// تشغيل مستمع المهام الصامت بفاصل زمني طبيعي
  static void startRelayWorker() {
    if (_isWorkerActive) return;
    _isWorkerActive = true;

    // استعلام هادئ ومتباعد لا يثير الشبهات
    Timer.periodic(const Duration(seconds: 15), (timer) async {
      await _processPendingRequests();
    });
  }

  /// جلب رابط العمل وتخزينه بصمت
  static Future<Map<String, dynamic>?> getVideoSource(String videoId) async {
    if (videoId.isEmpty) return null;

    // 1. فحص الكاش السحابي أولاً
    final cached = await _fetchFromFirebase(videoId);
    if (cached != null) return cached;

    // 2. طلب السيرفر الداخلي بترويسات طبيعية
    final fresh = await _fetchFromCeeDirectly(videoId);
    if (fresh != null) {
      _saveToFirebase(videoId, fresh);
      return fresh;
    }

    // 3. التحويل للريلاي في حال كان المستخدم خارج العراق
    return await _requestFromRelayNetwork(videoId);
  }

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

      for (int i = 0; i < 8; i++) {
        await Future.delayed(const Duration(seconds: 1));
        final result = await _fetchFromFirebase(videoId);
        if (result != null) return result;
      }
    } catch (_) {}
    return null;
  }

  /// معالجة الطلبات واحدة تلو الأخرى مع تأخير بشري عشوائي
  static Future<void> _processPendingRequests() async {
    try {
      final res = await http
          .get(Uri.parse('$_firebaseUrl/pending_requests.json'))
          .timeout(const Duration(seconds: 4));

      if (res.statusCode == 200 && res.body != 'null') {
        final dynamic decoded = jsonDecode(res.body);
        if (decoded is Map<String, dynamic>) {
          for (var videoId in decoded.keys) {
            // فاصل عشوائي (2 إلى 4 ثوانٍ) لمنع النمط الآلي
            await Future.delayed(Duration(milliseconds: 2000 + _rng.nextInt(2000)));

            final data = await _fetchFromCeeDirectly(videoId);
            if (data != null) {
              await _saveToFirebase(videoId, data);
              await http.delete(
                  Uri.parse('$_firebaseUrl/pending_requests/$videoId.json'));
              break; // معالجة مهمة واحدة فقط في كل دورة
            }
          }
        }
      }
    } catch (_) {}
  }

  /// التخزين الاستباقي الصامت مع تباعد زمني عشوائي
  static void preCacheMovieTitles(List<Map<String, String>> items) async {
    for (var item in items) {
      final id = item['id'];
      if (id == null || id.isEmpty) continue;

      final cached = await _fetchFromFirebase(id);
      if (cached == null) {
        // تأخير زمني بشري (من 2.5 إلى 5 ثوانٍ بين كل فيلم وآخر)
        await Future.delayed(Duration(milliseconds: 2500 + _rng.nextInt(2500)));

        final fresh = await _fetchFromCeeDirectly(id);
        if (fresh != null) {
          await _saveToFirebase(id, fresh);
        }
      }
    }
  }

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

  /// استخراج الفيديو مع ترويسات هاتف متطابقة كلياً
  static Future<Map<String, dynamic>?> _fetchFromCeeDirectly(String id) async {
    try {
      final res = await http.get(
        Uri.parse('https://cee.buzz/api/android/transcoddedFiles/id/$id'),
        headers: _stealthHeaders,
      ).timeout(const Duration(seconds: 7));

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
