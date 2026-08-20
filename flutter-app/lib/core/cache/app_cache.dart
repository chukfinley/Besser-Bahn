import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class AppCache {
  static const _prefix = 'cache_';

  static Future<void> save(String key, Map<String, dynamic> value) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(
      '$_prefix$key',
      jsonEncode({
        'createdAt': DateTime.now().toIso8601String(),
        'data': value,
      }),
    );
  }

  static Future<Map<String, dynamic>?> read(String key) async {
    final prefs = await SharedPreferences.getInstance();

    final raw = prefs.getString('$_prefix$key');

    if (raw == null) return null;

    final json = jsonDecode(raw) as Map<String, dynamic>;

    return json;
  }

  static Future<void> remove(String key) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.remove('$_prefix$key');
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();

    final keys = prefs.getKeys().where((k) => k.startsWith(_prefix));

    for (final key in keys) {
      await prefs.remove(key);
    }
  }
}
