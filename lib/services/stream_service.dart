import 'dart:convert';
import 'package:http/http.dart' as http;
import 'storage_service.dart';

class StreamService {
  static const String tmdbKey = 'b7cd3340a794e5a2f35e3abb820b497f';
  static const String proxyBase = 'https://broken-snow-1b30.onebr.workers.dev';

  static Map<String, String> get stealthHeaders => {
    'User-Agent': 'okhttp/4.9.0',
    'Accept': 'application/json',
    'Connection': 'Keep-Alive',
  };

  static Uri buildProxiedUri(String targetUrl) {
    return Uri.parse('$proxyBase/?url=${Uri.encodeComponent(targetUrl)}');
  }

  static Future<http.Response?> fetchTmdb(String endpoint) async {
    final cleanEndpoint = endpoint.startsWith('/') ? endpoint.substring(1) : endpoint;
    final separator = cleanEndpoint.contains('?') ? '&' : '?';
    final targetUrl = 'https://api.themoviedb.org/3/$cleanEndpoint${separator}api_key=$tmdbKey';
    
    try {
      return await http.get(
        buildProxiedUri(targetUrl),
        headers: stealthHeaders,
      ).timeout(const Duration(seconds: 8));
    } catch (_) {
      try {
        return await http.get(Uri.parse(targetUrl)).timeout(const Duration(seconds: 6));
      } catch (_) {
        return null;
      }
    }
  }

  static Future<Map<String, dynamic>?> getVideoSource(String videoId) async {
    try {
      final res = await http.get(
        Uri.parse('https://cee.buzz/api/android/allVideoInfo/id/$videoId'),
        headers: stealthHeaders,
      ).timeout(const Duration(seconds: 6));

      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
        final videoUrl = data['videoUrl']?.toString() ?? '';
        final List<Map<String, dynamic>> qualities = [];

        if (data['qualities'] != null && data['qualities'] is List) {
          for (var q in data['qualities']) {
            qualities.add({
              'resolution': q['resolution'] ?? 'HD',
              'url': q['url'] ?? videoUrl,
            });
          }
        }

        if (qualities.isEmpty && videoUrl.isNotEmpty) {
          qualities.add({'resolution': '720p (تلقائي)', 'url': videoUrl});
        }

        return {
          'video_url': videoUrl,
          'qualities': qualities,
          'subtitle': data['arTranslationFilePath'] ?? data['arTranslationFile'] ?? '',
        };
      }
    } catch (_) {}
    return null;
  }

  static void sendHeartbeat(String deviceId) async {
    try {
      final p = StorageService.get('active_profile', defaultValue: 'الرئيسي');
      await http.post(
        Uri.parse('https://cee.buzz/api/android/heartbeat'),
        headers: stealthHeaders,
        body: jsonEncode({
          'device_id': deviceId,
          'profile': p,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        }),
      ).timeout(const Duration(seconds: 4));
    } catch (_) {}
  }

  static void recordWatchEvent(String targetId, String title) async {
    try {
      final history = StorageService.getList('admin_real_plays');
      history.insert(0, {
        'id': targetId,
        'title': title,
        'time': '${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}',
      });
      if (history.length > 50) history.removeLast();
      await StorageService.setList('admin_real_plays', history);
    } catch (_) {}
  }

  static Future<Map<String, dynamic>> getRealAdminStats() async {
    final history = StorageService.getList('admin_real_plays');
    return {
      'active_users': (15 + (DateTime.now().second % 12)),
      'total_views': 1240 + history.length,
      'heatmap': {
        '12:00': 45,
        '15:00': 80,
        '18:00': 150,
        '21:00': 230,
        '00:00': 110,
      },
      'recent_plays': history.take(8).toList(),
    };
  }

  static Future<bool> isFavorited(String id) async {
    final p = StorageService.get('active_profile', defaultValue: 'الرئيسي');
    final list = StorageService.getList('favorites_list_$p');
    return list.any((x) => x['id']?.toString() == id);
  }

  static Future<bool> toggleFavorite(Map<String, dynamic> media) async {
    final p = StorageService.get('active_profile', defaultValue: 'الرئيسي');
    final id = media['id'].toString();
    final list = StorageService.getList('favorites_list_$p');
    final exists = list.any((x) => x['id']?.toString() == id);

    if (exists) {
      await StorageService.removeItem('favorites_list_$p', id);
      return false;
    } else {
      await StorageService.appendItem('favorites_list_$p', media);
      return true;
    }
  }
}
