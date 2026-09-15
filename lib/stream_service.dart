import 'dart:convert';
import 'package:http/http.dart' as http;

class StreamService {
  static const Map<String, String> stealthHeaders = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept': 'application/json, text/plain, */*',
    'Connection': 'keep-alive',
    'Referer': 'https://cee.buzz/',
  };

  static Future<List<dynamic>> fetchFeed({
    required bool isSeries,
    int page = 0,
    int perPage = 30,
    int level = 0,
  }) async {
    try {
      final vKind = isSeries ? 2 : 1;
      final url = 'https://cee.buzz/api/android/video/V/2/itemsPerPage/$perPage/level/$level/videoKind/$vKind/sortParam/desc/pageNumber/$page';
      final res = await http.get(Uri.parse(url), headers: stealthHeaders).timeout(const Duration(seconds: 12));

      if (res.statusCode == 200) {
        dynamic data = jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
        List list = (data is List) ? data : (data['articles'] ?? data['info'] ?? []);
        for (var item in list) {
          item['is_series_fixed'] = isSeries;
        }

        if (level == 2) {
          return list.where((item) {
            final title = ((item['ar_title'] ?? '') + (item['en_title'] ?? '')).toString().toLowerCase();
            final cats = (item['categories'] is List) ? jsonEncode(item['categories']).toLowerCase() : '';
            return cats.contains('animation') || cats.contains('family') || cats.contains('رسوم') ||
                   title.contains('moana') || title.contains('zenon') || title.contains('كرتون');
          }).toList();
        } else if (level == 1) {
          return list.where((item) {
            final cats = (item['categories'] is List) ? jsonEncode(item['categories']).toLowerCase() : '';
            return !cats.contains('horror') && !cats.contains('رعب');
          }).toList();
        }

        return list;
      }
    } catch (_) {}
    return [];
  }

  static Future<List<dynamic>> fetchByCategoryName(
    String categoryEn, {
    int page = 0,
    int level = 0,
  }) async {
    try {
      final start = page * 4;
      final requests = <Future<List<dynamic>>>[];
      for (int i = 0; i < 4; i++) {
        requests.add(fetchFeed(isSeries: false, page: start + i, perPage: 30, level: level));
        requests.add(fetchFeed(isSeries: true, page: start + i, perPage: 30, level: level));
      }

      final results = await Future.wait(requests);
      final List<dynamic> allItems = [];
      final Set<String> ids = {};

      for (var r in results) {
        for (var it in r) {
          final id = (it['nb'] ?? it['id'])?.toString();
          if (id != null && !ids.contains(id)) {
            ids.add(id);
            allItems.add(it);
          }
        }
      }

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
        if (target == 'horror' || target == 'رعب') {
          final en = (item['en_title'] ?? '').toString().toLowerCase();
          final ar = (item['ar_title'] ?? '').toString().toLowerCase();
          final desc = ((item['ar_content'] ?? '') + (item['en_content'] ?? '')).toString().toLowerCase();
          if (en.contains('horror') || ar.contains('رعب') || en.contains('ghost') || en.contains('dead') ||
              en.contains('evil') || en.contains('blood') || desc.contains('رعب') || desc.contains('خارق') ||
              desc.contains('أشباح') || desc.contains('موتى') || desc.contains('شياطين') || desc.contains('وحش')) {
            return true;
          }
        }
        return false;
      }).toList();
    } catch (_) {}
    return [];
  }

  /// مسار البحث المباشر المطابق لنظام cee.buzz
  static Future<List<dynamic>> searchContent(String query, {int level = 0}) async {
    final cleanQ = query.trim();
    if (cleanQ.isEmpty) return [];

    final enc = Uri.encodeComponent(cleanQ);

    // 1. المسار الحي الداخلي للبحث في cee
    try {
      final url = 'https://cee.buzz/api/search/live?query=$enc';
      final res = await http.get(Uri.parse(url), headers: stealthHeaders).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        dynamic data = jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
        List list = (data is List) ? data : (data['results'] ?? data['data'] ?? []);
        if (list.isNotEmpty) return list;
      }
    } catch (_) {}

    // 2. مسار البحث المباشر videoTitle
    try {
      final url2 = 'https://cee.buzz/api/android/video/videoTitle/$enc/level/$level';
      final res2 = await http.get(Uri.parse(url2), headers: stealthHeaders).timeout(const Duration(seconds: 8));

      if (res2.statusCode == 200) {
        dynamic data = jsonDecode(utf8.decode(res2.bodyBytes, allowMalformed: true));
        List list = (data is List) ? data : (data['articles'] ?? data['info'] ?? data['results'] ?? []);

        final matched = list.where((it) {
          final tAr = (it['ar_title'] ?? '').toString().toLowerCase();
          final tEn = (it['en_title'] ?? '').toString().toLowerCase();
          final qLower = cleanQ.toLowerCase();
          return tAr.contains(qLower) || tEn.contains(qLower);
        }).toList();

        if (matched.isNotEmpty) return matched;
      }
    } catch (_) {}

    // 3. مسار البحث المتقدم video_title_search
    try {
      final url3 = 'https://cee.buzz/api/android/video/V/2/itemsPerPage/50/video_title_search/$enc/pageNumber/0/level/$level';
      final res3 = await http.get(Uri.parse(url3), headers: stealthHeaders).timeout(const Duration(seconds: 8));

      if (res3.statusCode == 200) {
        dynamic data = jsonDecode(utf8.decode(res3.bodyBytes, allowMalformed: true));
        List list = (data is List) ? data : (data['articles'] ?? data['info'] ?? data['results'] ?? []);

        final matched = list.where((it) {
          final tAr = (it['ar_title'] ?? '').toString().toLowerCase();
          final tEn = (it['en_title'] ?? '').toString().toLowerCase();
          final qLower = cleanQ.toLowerCase();
          return tAr.contains(qLower) || tEn.contains(qLower);
        }).toList();

        if (matched.isNotEmpty) return matched;
      }
    } catch (_) {}

    return [];
  }

  static Future<Map<String, dynamic>?> getVideoSource(String videoId) async {
    try {
      final transRes = await http.get(
        Uri.parse('https://cee.buzz/api/android/transcoddedFiles/id/$videoId'),
        headers: stealthHeaders,
      ).timeout(const Duration(seconds: 10));

      List<Map<String, dynamic>> qualities = [];
      String mainVideoUrl = '';

      if (transRes.statusCode == 200) {
        dynamic filesData = jsonDecode(utf8.decode(transRes.bodyBytes, allowMalformed: true));
        List list = (filesData is List) ? filesData : [];

        for (var item in list) {
          final res = item['resolution']?.toString() ?? '360p';
          final url = item['videoUrl']?.toString() ?? '';
          if (url.isNotEmpty) {
            qualities.add({'resolution': res, 'url': url});
          }
        }

        if (qualities.isNotEmpty) {
          Map<String, dynamic>? selected;
          for (var q in ['360p', '480p', '240p', '720p', '1080p']) {
            final match = qualities.firstWhere(
              (item) => item['resolution'] == q,
              orElse: () => {},
            );
            if (match.isNotEmpty) {
              selected = match;
              break;
            }
          }
          mainVideoUrl = selected?['url'] ?? qualities.first['url'];
        }
      }

      if (mainVideoUrl.isEmpty) {
        final infoRes = await http.get(
          Uri.parse('https://cee.buzz/api/android/allVideoInfo/id/$videoId'),
          headers: stealthHeaders,
        ).timeout(const Duration(seconds: 8));

        if (infoRes.statusCode == 200) {
          dynamic infoData = jsonDecode(utf8.decode(infoRes.bodyBytes, allowMalformed: true));
          mainVideoUrl = infoData['videoUrl']?.toString() ?? '';
          if (mainVideoUrl.isNotEmpty) {
            qualities.add({'resolution': '360p', 'url': mainVideoUrl});
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

  static Future<Map<String, dynamic>> getVideoExtendedInfo(String videoId) async {
    try {
      final res = await http.get(
        Uri.parse('https://cee.buzz/api/android/allVideoInfo/id/$videoId'),
        headers: stealthHeaders,
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        return jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
      }
    } catch (_) {}
    return {};
  }

  static Future<List<dynamic>> getSeriesEpisodes(String seriesId) async {
    try {
      final res = await http.get(
        Uri.parse('https://cee.buzz/api/android/videoSeason/id/$seriesId'),
        headers: stealthHeaders,
      ).timeout(const Duration(seconds: 10));

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

  static String extractPoster(Map<String, dynamic> item, {bool highRes = false}) {
    if (highRes) {
      if (item['imgObjUrl'] != null && item['imgObjUrl'].toString().isNotEmpty) {
        return item['imgObjUrl'].toString();
      }
    }
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
