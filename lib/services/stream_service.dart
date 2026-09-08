import 'dart:convert';
import 'package:http/http.dart' as http;
import 'storage_service.dart';

class StreamService {
  static const String tmdbKey = '87a55d4914c4da1fcb2d49150036147f';
  static const String proxyBase = 'https://broken-smoke-fb0b.onbr.workers.dev';

  static Map<String, String> get stealthHeaders => {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
    'Accept': 'application/json',
  };

  static Future<Map<String, dynamic>?> fetchTmdb(String endpoint) async {
    final sep = endpoint.contains('?') ? '&' : '?';
    final targetUrl = 'https://api.themoviedb.org/3$endpoint${sep}api_key=$tmdbKey&include_adult=false';
    final proxiedUrl = '$proxyBase/?url=${Uri.encodeComponent(targetUrl)}';

    try {
      // محاولة الجلب عبر البروكسي أولاً
      final res = await http.get(Uri.parse(proxiedUrl), headers: stealthHeaders).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        return jsonDecode(res.body);
      }
    } catch (_) {}

    // محاولة اتصال احتياطية مباشرة في حال تعطل البروكسي
    try {
      final resDirect = await http.get(Uri.parse(targetUrl), headers: stealthHeaders).timeout(const Duration(seconds: 8));
      if (resDirect.statusCode == 200) {
        return jsonDecode(resDirect.body);
      }
    } catch (_) {}

    return null;
  }

  static Future<Map<String, dynamic>> getStream(String id, {String type = 'movie'}) async {
    // محرك البث المتوافق مع التطبيق
    final streamUrl = 'https://vidsrc.to/embed/$type/$id';
    return {
      'video_url': streamUrl,
      'qualities': ['1080p', '720p', '480p'],
    };
  }

  // المفضلة
  static bool isFavorite(String id) {
    final list = StorageService.getList('favorites_list');
    return list.any((e) => e['id'].toString() == id);
  }

  static void toggleFavorite(String id, Map<String, dynamic> media) {
    if (isFavorite(id)) {
      StorageService.removeItem('favorites_list', id);
    } else {
      StorageService.appendItem('favorites_list', media);
    }
  }

  // المشاهدة لاحقاً
  static bool isWatchLater(String id) {
    final list = StorageService.getList('watch_later_list');
    return list.any((e) => e['id'].toString() == id);
  }

  static void toggleWatchLater(String id, Map<String, dynamic> media) {
    if (isWatchLater(id)) {
      StorageService.removeItem('watch_later_list', id);
    } else {
      StorageService.appendItem('watch_later_list', media);
    }
  }

  // سجل المشاهدة والنبضات
  static void recordWatchHistory(String id, String title) {
    StorageService.appendItem('history_list', {
      'id': id,
      'title': title,
      'time': DateTime.now().toIso8601String(),
    });
  }

  static void sendHeartbeat(String devId) {}
}
