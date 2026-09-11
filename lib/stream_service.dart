import 'dart:convert';
import 'package:http/http.dart' as http;

class StreamService {
  static const Map<String, String> stealthHeaders = {
    'User-Agent': 'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Mobile Safari/537.36',
    'Accept': '*/*',
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
      final res = await http.get(Uri.parse(url), headers: stealthHeaders).timeout(const Duration(seconds: 8));

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
      final start = page * 6;
      final requests = <Future<List<dynamic>>>[];
      for (int i = 0; i < 6; i++) {
        requests.add(fetchFeed(isSeries: false, page: start + i, perPage: 40, level: level));
        requests.add(fetchFeed(isSeries: true, page: start + i, perPage: 40, level: level));
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

  static Future<List<dynamic>> searchContent(String query, {int level = 0}) async {
    if (query.trim().isEmpty) return [];
    try {
      final b64 = base64.encode(utf8.encode(query.trim()));
      final url = 'https://cee.buzz/api/android/video/V/2/itemsPerPage/40/video_title_search/$b64/itemsPerPage/40/pageNumber/0/level/$level';
      final res = await http.get(Uri.parse(url), headers: stealthHeaders).timeout(const Duration(seconds: 7));

      if (res.statusCode == 200) {
        dynamic data = jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
        List list = (data is List) ? data : (data['articles'] ?? data['info'] ?? []);
        if (list.isNotEmpty) return list;
      }
    } catch (_) {}

    try {
      final qLower = query.toLowerCase().trim();
      final feed = await fetchFeed(isSeries: false, page: 0, perPage: 80, level: level);
      final feedSeries = await fetchFeed(isSeries: true, page: 0, perPage: 80, level: level);
      final all = [...feed, ...feedSeries];
      return all.where((it) {
        final ar = (it['ar_title'] ?? '').toString().toLowerCase();
        final en = (it['en_title'] ?? '').toString().toLowerCase();
        return ar.contains(qLower) || en.contains(qLower);
      }).toList();
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
          // تفضيل جودة خفيفة تبدأ فوراً على شبكة 2Mbps
          Map<String, dynamic>? selected;
          for (var q in ['360p', '240p', '480p', '720p']) {
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

  static Future<Map<String, dynamic>> getVideoExtendedInfo(String videoId) async {
    try {
      final res = await http.get(
        Uri.parse('https://cee.buzz/api/android/allVideoInfo/id/$videoId'),
        headers: stealthHeaders,
      ).timeout(const Duration(seconds: 6));

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
