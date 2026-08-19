import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/journey_search.dart';

class SearchHistoryCache {
  static const _key = 'search_history';

  Future<List<JourneySearch>> read() async {
    final prefs = await SharedPreferences.getInstance();

    final data = prefs.getString(_key);

    if (data == null) {
      return [];
    }

    final list = jsonDecode(data) as List<dynamic>;

    return list
        .whereType<Map<String, dynamic>>()
        .map(JourneySearch.fromJson)
        .toList();
  }

  Future<void> write(List<JourneySearch> searches) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(
      _key,
      jsonEncode(searches.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> add(JourneySearch search) async {
    final current = await read();

    current.removeWhere((e) => e.from == search.from && e.to == search.to);

    current.insert(0, search);

    if (current.length > 10) {
      current.removeLast();
    }

    await write(current);
  }
}
