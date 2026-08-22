import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/journey.dart';
import 'cache/cache_entry.dart';
import 'cache/cache_policy.dart';

class JourneyCache {
  static String key({
    required String from,
    required String to,
    required DateTime dateTime,
    required bool arrival,
  }) {
    return '${from}_${to}_${dateTime.toIso8601String()}_$arrival';
  }

  static Future<void> write(String key, JourneyResult result) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(
      key,
      jsonEncode({
        'createdAt': DateTime.now().toIso8601String(),
        'data': result.toJson(),
      }),
    );
  }

  static Future<CacheEntry<JourneyResult>?> read(String key) async {
    final prefs = await SharedPreferences.getInstance();

    final raw = prefs.getString(key);

    if (raw == null) return null;

    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;

      final createdAt = DateTime.parse(json['createdAt'] as String);
      final data = JourneyResult.fromJson(json['data'] as Map<String, dynamic>);

      return CacheEntry(data: data, createdAt: createdAt);
    } catch (_) {
      await prefs.remove(key);
      return null;
    }
  }

  static bool isFresh(CacheEntry<JourneyResult> entry) {
    return !entry.isExpired(CachePolicy.journeySearch.ttl);
  }
}
