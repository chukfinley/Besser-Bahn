import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/journey.dart';

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

    await prefs.setString(key, jsonEncode(result.toJson()));
  }

  static Future<JourneyResult?> read(String key) async {
    final prefs = await SharedPreferences.getInstance();

    final raw = prefs.getString(key);

    if (raw == null) return null;

    try {
      return JourneyResult.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      await prefs.remove(key);
      return null;
    }
  }
}
