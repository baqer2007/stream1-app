import 'dart:convert';
import 'package:http/http.dart' as http;

class StreamService {
  static Map<String, String> get stealthHeaders => {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36',
    'Accept': 'application/json, text/plain, */*',
    'Referer': 'https://cee.buzz/',
  };

  static void startRelayWorker() {}
  static void sendHeartbeat(String deviceId) {}
  static void recordWatchEvent(String targetId, String title) {}

  /// جلب قوائم الأفلام والمسلسلات مباشرة للصفحة الرئيسية
  /// level = 0 (أفلام) | level = 1 (مسلسلات)
  static Future<List<dynamic>> fetchHomeFeed({int level = 0, int page = 0, int perPage = 24}) async {
    try {
      final url = 'https://cee.buzz/api/android/video/V/2/itemsPerPage/$perPage/pageNumber/$page/level/$level';
      final res = await http.get(Uri.parse(url), headers: stealthHeaders).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        dynamic data = jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
        if (data is List) return data;
        if (data['articles'] is List) return data['articles'];
      }
    } catch (_) {}
    return [];
  }

  /// البحث المباشر في سيرفر سينمانا
  static Future<List<dynamic>> searchContent(String query, {int level = 0}) async {
    try {
      final b64 = base64.encode(utf8.encode(query.trim()));
      final url = 'https://cee.buzz/api/android/video/V/2/itemsPerPage/30/video_title_search/$b64/itemsPerPage/30/pageNumber/0/level/$level';
      final res = await http.get(Uri.parse(url), headers: stealthHeaders).timeout(const Duration(seconds: 7));

      if (res.statusCode == 200) {
        dynamic data = jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
        if (data is List) return data;
        if (data['articles'] is List) return data['articles'];
      }
    } catch (_) {}
    return [];
  }

  /// استخراج روابط الفيديو المباشرة والجودات
  static Future<Map<String, dynamic>?> getVideoSource(String videoId) async {
    try {
      final transRes = await http.get(
        Uri.parse('https://cee.buzz/api/android/transcoddedFiles/id/$videoId'),
        headers: stealthHeaders,
      ).timeout(const Duration(seconds: 8));

      List<Map<String, dynamic>> qualities = [];
      String mainVideoUrl = '';

      if (transRes.statusCode == 200) {
        dynamic filesData = jsonDecode(utf8.decode(transRes.bodyBytes, allowMalformed: true));
        List list = (filesData is List) ? filesData : [];

        for (var item in list) {
          final res = item['resolution']?.toString() ?? '720p';
          final url = item['videoUrl']?.toString() ?? '';
          if (url.isNotEmpty) {
            qualities.add({'resolution': res, 'url': url});
          }
        }

        if (qualities.isNotEmpty) {
          final defaultQuality = qualities.firstWhere(
            (q) => q['resolution'] == '720p',
            orElse: () => qualities.last,
          );
          mainVideoUrl = defaultQuality['url'];
        }
      }

      if (mainVideoUrl.isEmpty) {
        final infoRes = await http.get(
          Uri.parse('https://cee.buzz/api/android/allVideoInfo/id/$videoId'),
          headers: stealthHeaders,
        ).timeout(const Duration(seconds: 6));

        if (infoRes.statusCode == 200) {
          dynamic infoData = jsonDecode(utf8.decode(infoRes.bodyBytes, allowMalformed: true));
          mainVideoUrl = infoData['videoUrl']?.toString() ?? '';
          if (mainVideoUrl.isNotEmpty) {
            qualities.add({'resolution': '720p', 'url': mainVideoUrl});
          }
        }
      }

      if (mainVideoUrl.isNotEmpty) {
        return {
          'video_url': mainVideoUrl,
          'qualities': qualities,
        };
      }
    } catch (_) {}
    return null;
  }

  /// استخراج رابط الترجمة العربية
  static Future<String> getArabicSubtitleUrl(String videoId) async {
    try {
      final res = await http.get(
        Uri.parse('https://cee.buzz/api/android/allVideoInfo/id/$videoId'),
        headers: stealthHeaders,
      ).timeout(const Duration(seconds: 6));

      if (res.statusCode == 200) {
        dynamic data = jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
        return data['arTranslationFilePath']?.toString() ?? data['arTranslationFile']?.toString() ?? '';
      }
    } catch (_) {}
    return '';
  }

  /// جلب حلقات المسلسل مباشرة
  static Future<List<dynamic>> getSeriesEpisodes(String seriesId) async {
    try {
      final res = await http.get(
        Uri.parse('https://cee.buzz/api/android/video/V/2/itemsPerPage/250/parent_id/$seriesId/itemsPerPage/250/pageNumber/0/level/2'),
        headers: stealthHeaders,
      ).timeout(const Duration(seconds: 7));

      if (res.statusCode == 200) {
        dynamic data = jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
        if (data is List) return data;
        if (data['articles'] is List) return data['articles'];
      }
    } catch (_) {}
    return [];
  }

  /// مساعدة لاستخراج رابط البوستر من الكائن
  static String extractPoster(Map<String, dynamic> item) {
    if (item['imgMediumThumbObjUrl'] != null && item['imgMediumThumbObjUrl'].toString().isNotEmpty) {
      return item['imgMediumThumbObjUrl'].toString();
    }
    if (item['imgThumbObjUrl'] != null && item['imgThumbObjUrl'].toString().isNotEmpty) {
      return item['imgThumbObjUrl'].toString();
    }
    if (item['img'] != null && item['img'].toString().isNotEmpty) {
      return 'https://cnth2.cee.buzz/vascin-poster-images/${item['img']}';
    }
    return '';
  }
}
