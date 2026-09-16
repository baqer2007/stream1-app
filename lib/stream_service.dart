import 'dart:convert';
import 'package:http/http.dart' as http;

class StreamSecurity {
  // مفتاح تشفير عشوائي خاص بك
  static const int _xorKey = 0x6E;

  // فك التشفير في الذاكرة الحية لحظة الطلب فقط
  static String decrypt(List<int> bytes) {
    return String.fromCharCodes(bytes.map((b) => b ^ _xorKey));
  }
}

class StreamService {
  // الرابط المشفر لـ: "https://cee.buzz/api/android"
  static final List<int> _encBaseUrl = [
    0x4e, 0x52, 0x52, 0x56, 0x55, 0x1c, 0x49, 0x49, 
    0x45, 0x43, 0x43, 0x08, 0x44, 0x53, 0x5c, 0x5c, 
    0x49, 0x47, 0x56, 0x4f, 0x49, 0x47, 0x48, 0x42, 
    0x49, 0x47, 0x4b
  ];

  static String get _baseUrl {
    // ينتج: https://cee.buzz/api/android
    return StreamSecurity.decrypt([
      42, 58, 58, 46, 45, 122, 119, 119, 57, 59, 59, 112, 56, 47, 40, 40, 119, 63, 46, 51, 119, 63, 48, 58, 44, 49, 48
    ]);
  }

  static String get _cdnImages {
    // ينتج: https://cnth2.cee.buzz/vascin-poster-images/
    return StreamSecurity.decrypt([
      42, 58, 58, 46, 45, 122, 119, 119, 57, 48, 58, 54, 108, 112, 57, 59, 59, 112, 56, 47, 40, 40, 119, 44, 63, 45, 57, 55, 48, 115, 46, 49, 45, 58, 59, 44, 115, 55, 47, 63, 53, 59, 45, 119
    ]);
  }

  static final Map<String, String> stealthHeaders = {
    'User-Agent': 'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36',
    'Accept': 'application/json, text/plain, */*',
    'Connection': 'keep-alive',
    'Referer': StreamSecurity.decrypt([42, 58, 58, 46, 45, 122, 119, 119, 57, 59, 59, 112, 56, 47, 40, 40, 119]), // https://cee.buzz/
  };

  static Future<List<dynamic>> fetchFeed({
    required bool isSeries,
    int page = 0,
    int perPage = 30,
    int level = 0,
  }) async {
    try {
      final vKind = isSeries ? 2 : 1;
      final url = '$_baseUrl/video/V/2/itemsPerPage/$perPage/level/$level/videoKind/$vKind/sortParam/desc/pageNumber/$page';
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

  static Future<List<dynamic>> searchContent(String query, {int level = 0}) async {
    final cleanQ = query.trim();
    if (cleanQ.isEmpty) return [];

    try {
      String b64 = base64.encode(utf8.encode(cleanQ)).replaceAll('=', '');
      final url = '$_baseUrl/video/V/2/itemsPerPage/20/video_title_search/$b64/itemsPerPage/12/pageNumber/0/level/$level';

      final res = await http.get(Uri.parse(url), headers: stealthHeaders).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        dynamic data = jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
        List list = (data is List) ? data : (data['articles'] ?? data['info'] ?? []);
        return list;
      }
    } catch (_) {}

    return [];
  }

  static Future<Map<String, dynamic>?> getVideoSource(String videoId) async {
    try {
      final transRes = await http.get(
        Uri.parse('$_baseUrl/transcoddedFiles/id/$videoId'),
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
          Uri.parse('$_baseUrl/allVideoInfo/id/$videoId'),
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
        Uri.parse('$_baseUrl/allVideoInfo/id/$videoId'),
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
        Uri.parse('$_baseUrl/videoSeason/id/$seriesId'),
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

  static Future<List<Map<String, int>>> fetchCeeSkippingDurations(String mediaId) async {
    try {
      final url = Uri.parse('$_baseUrl/skippingDurations/id/$mediaId');
      final response = await http.get(url, headers: stealthHeaders).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final dynamic decoded = jsonDecode(utf8.decode(response.bodyBytes, allowMalformed: true));
        if (decoded is Map<String, dynamic>) {
          final List starts = decoded['start'] ?? [];
          final List ends = decoded['end'] ?? [];

          List<Map<String, int>> results = [];
          final len = starts.length < ends.length ? starts.length : ends.length;

          for (int i = 0; i < len; i++) {
            final startSec = (double.tryParse(starts[i].toString()) ?? 0.0).floor();
            final endSec = (double.tryParse(ends[i].toString()) ?? 0.0).ceil();
            if (endSec > startSec) {
              results.add({'start': startSec, 'end': endSec});
            }
          }
          return results;
        }
      }
    } catch (_) {}
    return [];
  }

  static String extractPoster(dynamic item, {bool highRes = false}) {
    if (item == null) return '';
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
      return img.startsWith('http') ? img : '$_cdnImages$img';
    }
    return '';
  }
}
