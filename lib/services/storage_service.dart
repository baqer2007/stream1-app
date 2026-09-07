import 'package:hive_flutter/hive_flutter.dart';

class StorageService {
  static late Box _box;

  static Future<void> init() async {
    await Hive.initFlutter();
    _box = await Hive.openBox('onebr_tv_db');
  }

  static List<Map<String, dynamic>> getList(String key) {
    final raw = _box.get(key);
    if (raw == null) return [];
    try {
      return List<Map<String, dynamic>>.from(
        (raw as List).map((e) => Map<String, dynamic>.from(e as Map)),
      );
    } catch (_) {
      return [];
    }
  }

  static Future<void> setList(String key, List<Map<String, dynamic>> list) async {
    await _box.put(key, list);
  }

  static Future<void> appendItem(String key, Map<String, dynamic> item, {int maxLength = 35, String idField = 'id'}) async {
    final list = getList(key);
    list.removeWhere((x) => x[idField]?.toString() == item[idField]?.toString());
    list.insert(0, item);
    if (list.length > maxLength) list.removeRange(maxLength, list.length);
    await setList(key, list);
  }

  static Future<void> removeItem(String key, String id, {String idField = 'id'}) async {
    final list = getList(key);
    list.removeWhere((x) => x[idField]?.toString() == id);
    await setList(key, list);
  }

  static dynamic get(String key, {dynamic defaultValue}) => _box.get(key, defaultValue: defaultValue);
  static Future<void> put(String key, dynamic value) async => await _box.put(key, value);
  static Future<void> remove(String key) async => await _box.delete(key);
}
