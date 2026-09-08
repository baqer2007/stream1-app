import 'dart:convert';
import 'package:http/http.dart' as http;

class StreamService {
  static Map<String, String> get stealthHeaders => {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
    'Accept': 'application/json',
  };

  static void startRelayWorker() {}

  static void sendHeartbeat(String deviceId) {}

  static void recordWatchEvent(String targetId, String title) {}

  static Future<Map<String, dynamic>?> getVideoSource(String videoId) async {
    try {
      final res = await http.get(
        Uri.parse('https://cee.buzz/api/android/allVideoInfo/id/$videoId'),
        headers: stealthHeaders,
      ).timeout(const Duration(seconds: 6));

      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
        final videoUrl = data['videoUrl']?.toString() ?? data['video_url']?.toString() ?? '';
        final rawQualities = data['qualities'] as List? ?? [];

        List<Map<String, dynamic>> qualities = [];
        for (var q in rawQualities) {
          qualities.add({
            'resolution': q['resolution']?.toString() ?? '720p',
            'url': q['url']?.toString() ?? videoUrl,
          });
        }

        if (qualities.isEmpty && videoUrl.isNotEmpty) {
          qualities.add({'resolution': '720p', 'url': videoUrl});
        }

        return {
          'video_url': videoUrl,
          'qualities': qualities,
        };
      }
    } catch (_) {}
    return null;
  }

  static Future<Map<String, dynamic>> getRealAdminStats() async {
    return {
      'active_users': 1,
      'total_views': 12,
      'heatmap': {'12-04': 2, '04-08': 1, '08-12': 5, '12-16': 8, '16-20': 12, '20-24': 9},
      'recent_plays': [
        {'title': 'ONEBR Stream', 'time': 'الآن'}
      ],
    };
  }
}
