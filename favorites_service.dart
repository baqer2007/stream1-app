import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class FavoritesService {
  static const String _favKey = 'user_favorites_list';

  static Future<List<Map<String, dynamic>>> getFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_favKey);
    if (raw == null) return [];
    try {
      return List<Map<String, dynamic>>.from(jsonDecode(raw));
    } catch (_) {
      return [];
    }
  }

  static Future<bool> isFavorited(String id) async {
    final list = await getFavorites();
    return list.any((item) => item['id']?.toString() == id);
  }

  static Future<bool> toggleFavorite(Map<String, dynamic> media, String type) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await getFavorites();
    final id = media['id']?.toString();

    final exists = list.any((item) => item['id']?.toString() == id);
    if (exists) {
      list.removeWhere((item) => item['id']?.toString() == id);
      await prefs.setString(_favKey, jsonEncode(list));
      return false;
    } else {
      final toSave = Map<String, dynamic>.from(media);
      toSave['media_type'] = type;
      list.insert(0, toSave);
      await prefs.setString(_favKey, jsonEncode(list));
      return true;
    }
  }
}
