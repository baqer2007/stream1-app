import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class FavoritesService {
  static const String _favKey = 'user_favorites_list';

  static Future<List<Map<String, dynamic>>> getFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final rawData = prefs.getString(_favKey);
    if (rawData == null || rawData.isEmpty) return [];
    try {
      final List decoded = jsonDecode(rawData);
      return List<Map<String, dynamic>>.from(decoded);
    } catch (_) {
      return [];
    }
  }

  static Future<bool> isFavorited(String id) async {
    final list = await getFavorites();
    return list.any((item) => item['id'].toString() == id.toString());
  }

  static Future<bool> toggleFavorite(Map<String, dynamic> media, String type) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await getFavorites();
    final id = media['id'].toString();

    final existingIndex = list.indexWhere((item) => item['id'].toString() == id);

    if (existingIndex >= 0) {
      list.removeAt(existingIndex);
      await prefs.setString(_favKey, jsonEncode(list));
      return false;
    } else {
      list.insert(0, {
        'id': media['id'],
        'title': media['title'] ?? media['name'] ?? '',
        'poster_path': media['poster_path'],
        'vote_average': media['vote_average'],
        'release_date': media['release_date'] ?? media['first_air_date'] ?? '',
        'type': type,
      });
      await prefs.setString(_favKey, jsonEncode(list));
      return true;
    }
  }
}
