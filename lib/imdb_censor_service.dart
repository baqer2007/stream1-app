import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;

class ImdbCensorService {
  static const Map<String, String> _headers = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept-Language': 'en-US,en;q=0.9',
  };

  /// سحب فترات اللقطات الحساسة مباشرة عبر معرف العمل في IMDb
  static Future<List<Map<String, int>>> fetchSensitiveSegments(String imdbId) async {
    final List<Map<String, int>> segments = [];

    try {
      final url = Uri.parse('https://www.imdb.com/title/$imdbId/parentalguide');
      final response = await http.get(url, headers: _headers).timeout(
        const Duration(seconds: 8),
      );

      if (response.statusCode != 200) return [];

      final document = html_parser.parse(response.body);

      // العثور على قسم المشاهد الحساسة والعري (Sex & Nudity)
      final nuditySection = document.getElementById('advisories-nudity');
      if (nuditySection == null) return [];

      final text = nuditySection.text;

      // 1. استخراج الأوقات بصيغة HH:MM:SS أو MM:SS
      final timeRegex = RegExp(
        r'(?:at\s+|around\s+)?(?:(\d{1,2}):)?(\d{1,2}):(\d{2})',
        caseSensitive: false,
      );
      final matches = timeRegex.allMatches(text);

      for (final match in matches) {
        final hours = match.group(1) != null ? int.parse(match.group(1)!) : 0;
        final minutes = int.parse(match.group(2)!);
        final seconds = int.parse(match.group(3)!);

        final totalSeconds = (hours * 3600) + (minutes * 60) + seconds;

        // مدة تخطي تلقائية للمشهد 25 ثانية
        segments.add({
          'start': totalSeconds,
          'end': totalSeconds + 25,
        });
      }

      // 2. استخراج الأوقات المكتوبة بالدقائق الصريحة مثل (minute 45 أو min 45)
      final minRegex = RegExp(r'(?:minute|min)\s+(\d{1,3})', caseSensitive: false);
      final minMatches = minRegex.allMatches(text);

      for (final m in minMatches) {
        final minutes = int.parse(m.group(1)!);
        final totalSeconds = minutes * 60;
        segments.add({
          'start': totalSeconds,
          'end': totalSeconds + 30,
        });
      }

      // إزالة التكرارات
      final List<Map<String, int>> cleanSegments = [];
      final Set<int> seen = {};
      for (final s in segments) {
        if (!seen.contains(s['start'])) {
          seen.add(s['start']!);
          cleanSegments.add(s);
        }
      }

      return cleanSegments;
    } catch (_) {
      return [];
    }
  }
}
