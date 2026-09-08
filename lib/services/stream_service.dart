import 'dart:convert';
import 'package:http/http.dart' as http;
import 'storage_service.dart';

class StreamService {
  static const String tmdbKey = '87a55d4914c4da1fcb2d49150036147f';

  // جلب مباشر وسريع من TMDB بدون أي وسيط أو بروكسي
  static Future<Map<String, dynamic>?> fetchTmdb(String endpoint) async {
    final sep = endpoint.contains('?') ? '&' : '?';
    final url = 'https://api.themoviedb.org/3$endpoint${sep}api_key=$tmdbKey&language=ar';

    try {
      final res = await http.get(
        Uri.parse(url),
        headers: {
          'Accept': 'application/json',
          'User-Agent': 'Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36',
        },
      ).timeout(const Duration(seconds: 15));

      if (res.statusCode == 200) {
        return jsonDecode(utf8.decode(res.bodyBytes));
      }
    } catch (_) {
      try {
        final fallbackUrl = 'https://api.themoviedb.org/3$endpoint${sep}api_key=$tmdbKey';
        final resFallback = await http.get(Uri.parse(fallbackUrl)).timeout(const Duration(seconds: 10));
        if (resFallback.statusCode == 200) {
          return jsonDecode(utf8.decode(resFallback.bodyBytes));
        }
      } catch (_) {}
    }

    return null;
  }

  static Future<Map<String, dynamic>> getStream(String id, {String type = 'movie'}) async {
    final streamUrl = type == 'tv'
        ? 'https://vidsrc.xyz/embed/tv/$id/1/1'
        : 'https://vidsrc.xyz/embed/movie/$id';

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
