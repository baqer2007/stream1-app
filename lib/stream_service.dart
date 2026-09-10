import 'dart:convert';
import 'package:http/http.dart' as http;

class StreamService {
  static const Map<String, String> stealthHeaders = {
    'User-Agent': 'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Mobile Safari/537.36',
    'Accept': 'application/json, text/plain, */*',
    'Referer': 'https://cee.buzz/',
  };

  /// جلب دفعة من الأعمال العامة (أفلام أو مسلسلات)
  static Future<List<dynamic>> fetchFeed({required bool isSeries, int page = 0, int perPage = 30}) async {
    try {
      final vKind = isSeries ? 2 : 1;
      final url = 'https://cee.buzz/api/android/video/V/2/itemsPerPage/$perPage/level/0/videoKind/$vKind/sortParam/desc/pageNumber/$page';
      final res = await http.get(Uri.parse(url), headers: stealthHeaders).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        dynamic data = jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
        List list = (data is List) ? data : (data['articles'] ?? data['info'] ?? []);
        for (var item in list) {
          item['is_series_fixed'] = isSeries;
        }
        return list;
      }
    } catch (_) {}
    return [];
  }

  /// جلب وتصفية الأعمال بحسب اسم التصنيف الفعلي المكتشف
  static Future<List<dynamic>> fetchByCategoryName(String categoryEn, {int page = 0}) async {
    try {
      // جلب دفعة أفلام ودفعة مسلسلات/أنمي بالتوازي لجمع محتوى التصنيف كاملاً
      final results = await Future.wait([
        fetchFeed(isSeries: false, page: page, perPage: 40),
        fetchFeed(isSeries: true, page: page, perPage: 40),
      ]);

      final allItems = [...results[0], ...results[1]];
      final target = categoryEn.toLowerCase().trim();

      return allItems.where((item) {
        final cats = item['categories'];
        if (cats is List) {
          for (var c in cats) {
            final en = (c['en_title'] ?? '').toString().toLowerCase();
            final ar = (c['ar_title'] ?? '').toString().toLowerCase();
            if (en.contains(target) || ar.contains(target)) return true;
          }
        }

        // دعم خاص للأنمي والرسوم المتحركة
        if (target == 'animation' || target == 'anime') {
          final enTitle = (item['en_title'] ?? '').toString().toLowerCase();
          final arTitle = (item['ar_title'] ?? '').toString().toLowerCase();
          if (enTitle.contains('anime') || arTitle.contains('أنمي') || arTitle.contains('انمي')) return true;
        }
        return false;
      }).toList();
    } catch (_) {}
    return [];
  }

  /// البحث المباشر
  static Future<List<dynamic>> searchContent(String query) async {
    try {
      final b64 = base64.encode(utf8.encode(query.trim()));
      final url = 'https://cee.buzz/api/android/video/V/2/itemsPerPage/30/video_title_search/$b64/itemsPerPage/30/pageNumber/0/level/0';
      final res = await http.get(Uri.parse(url), headers: stealthHeaders).timeout(const Duration(seconds: 7));

      if (res.statusCode == 200) {
        dynamic data = jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
        if (data is List) return data;
        if (data is Map) return data['articles'] ?? data['info'] ?? [];
      }
    } catch (_) {}
    return [];
  }

  /// روابط الفيديو
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
          final res = item['resolution']?.toString() ?? '240p';
          final url = item['videoUrl']?.toString() ?? '';
          if (url.isNotEmpty) {
            qualities.add({'resolution': res, 'url': url});
          }
        }

        if (qualities.isNotEmpty) {
          final defaultQuality = qualities.firstWhere(
            (q) => q['resolution'] == '240p',
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
            qualities.add({'resolution': '240p', 'url': mainVideoUrl});
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

  /// استخراج الترجمة
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

  /// حلقات المسلسلات والأنمي
  static Future<List<dynamic>> getSeriesEpisodes(String seriesId) async {
    try {
      final res = await http.get(
        Uri.parse('https://cee.buzz/api/android/videoSeason/id/$seriesId'),
        headers: stealthHeaders,
      ).timeout(const Duration(seconds: 7));

      if (res.statusCode == 200) {
        dynamic data = jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
        if (data is List) return data;
        if (data is Map) {
          for (var key in ['episodes', 'articles', 'videos', 'seasons', 'info']) {
            if (data[key] is List && data[key].isNotEmpty) return data[key];
          }
        }
      }
    } catch (_) {}
    return [];
  }

  static String extractPoster(Map<String, dynamic> item) {
    if (item['imgMediumThumbObjUrl'] != null && item['imgMediumThumbObjUrl'].toString().isNotEmpty) {
      return item['imgMediumThumbObjUrl'].toString();
    }
    if (item['imgThumbObjUrl'] != null && item['imgThumbObjUrl'].toString().isNotEmpty) {
      return item['imgThumbObjUrl'].toString();
    }
    if (item['img'] != null && item['img'].toString().isNotEmpty) {
      final img = item['img'].toString();
      return img.startsWith('http') ? img : 'https://cnth2.cee.buzz/vascin-poster-images/$img';
    }
    return '';
  }
}
