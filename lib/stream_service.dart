import 'dart:convert';
import 'package:http/http.dart' as http;

class StreamService {
  static Map<String, String> get stealthHeaders => {
    'User-Agent': 'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36',
    'Accept': 'application/json, text/plain, */*',
    'Referer': 'https://cee.buzz/',
  };

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

  /// مسار جلب التصنيفات الحقيقي مع الفحص المزدوج
  static Future<List<dynamic>> fetchByCategory(int categoryId, {int page = 0, int? videoKind}) async {
    try {
      final offset = page * 30;
      
      // إذا كان التصنيف هو الأنمي، نستخدم البحث المباشر لتوفير قائمة أنمي يابانية حقيقية ومضمونة 100%
      if (categoryId == 999) {
        final animeKeywords = ['انمي', 'Anime', 'Attack on Titan', 'One Piece', 'Jujutsu', 'Demon Slayer'];
        final keyword = animeKeywords[page % animeKeywords.length];
        return await searchContent(keyword);
      }

      final url = 'https://cee.buzz/api/android/videosByCategory?categoryId=$categoryId&orderby=desc&videoKind=${videoKind ?? 1}&offset=$offset&level=0';
      final res = await http.get(Uri.parse(url), headers: stealthHeaders).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        dynamic data = jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
        List list = [];
        if (data is Map && data.containsKey('info') && data['info'] is List) {
          list = data['info'];
        } else if (data is List) {
          list = data;
        } else if (data is Map && data['articles'] is List) {
          list = data['articles'];
        }
        return list;
      }
    } catch (_) {}
    return [];
  }

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
      return 'https://cnth2.cee.buzz/vascin-poster-images/${item['img']}';
    }
    return '';
  }
}
