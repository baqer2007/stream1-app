import 'dart:convert';
import 'package:http/http.dart' as http;

class StreamService {
  // قاعدة بيانات Firebase الخاصة بمشروعك
  static const String _firebaseUrl = 'https://cee-stream-default-rtdb.firebaseio.com';

  /// الدالة الرئيسية: تبحث في الكاش أولاً، وإن لم تجده تطلبه من cee.buzz وتخزنه
  static Future<Map<String, dynamic>?> getVideoSource(String videoId) async {
    // 1. فحص هل الرابط مخزن مسبقاً في Firebase
    final cached = await _fetchFromFirebase(videoId);
    if (cached != null) {
      return cached;
    }

    // 2. الجلب المباشر من cee.buzz (من داخل العراق)
    final direct = await _fetchFromCee(videoId);
    if (direct != null) {
      // حفظه سحابياً ليستفيد منه المستخدمون في الخارج
      _saveToFirebase(videoId, direct);
      return direct;
    }

    return null;
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

  static Future<Map<String, dynamic>?> _fetchFromCee(String id) async {
    try {
      final res = await http.get(
        Uri.parse('https://cee.buzz/api/android/transcoddedFiles/id/$id'),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Linux; Android 10; Mobile) AppleWebKit/537.36',
          'Referer': 'https://cee.buzz/',
          'Accept': 'application/json, text/plain, */*',
        },
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        dynamic data = jsonDecode(res.body);
        List list = (data is List) ? data : (data['videos'] ?? []);
        if (list.isEmpty) return null;

        List<Map<String, String>> qualities = [];
        for (var item in list) {
          final resName = item['resolution']?.toString() ?? 'Auto';
          final url = item['videoUrl']?.toString() ?? item['videourl']?.toString() ?? item['url']?.toString();
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
