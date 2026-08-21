import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Persistent cache for trip route polylines (the exact track geometry from
/// HAFAS).
///
/// Keyed by the *physical route* (the ordered sequence of stop EVA ids), NOT
/// the trip id — a trip id embeds the date and changes daily, but the tracks
/// the ICE 801 runs on are the same every day. So once we've fetched a route's
/// geometry while HAFAS was reachable, every later view of that route is exact
/// even if the (flaky) HAFAS mirror is down.
class PolylineCache {
  PolylineCache._();
  static final PolylineCache instance = PolylineCache._();

  static const _kKey = 'polyline_cache_v1';

  /// Keep the persisted map bounded; routes are tiny but we don't want it to
  /// grow forever. Oldest insertions are dropped first.
  static const _kMaxRoutes = 300;

  /// In-memory layer. Insertion order = recency for the simple LRU trim.
  final Map<String, List<Map<String, double>>> _mem = {};
  bool _loaded = false;

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kKey);
      if (raw == null) return;
      final decoded = json.decode(raw) as Map<String, dynamic>;
      decoded.forEach((key, value) {
        final pts = (value as List<dynamic>)
            .whereType<List<dynamic>>()
            .where((p) => p.length >= 2)
            .map(
              (p) => {
                'lat': (p[0] as num).toDouble(),
                'lng': (p[1] as num).toDouble(),
              },
            )
            .toList();
        if (pts.isNotEmpty) _mem[key] = pts;
      });
    } catch (_) {
      // Corrupt cache → start empty; non-fatal.
    }
  }

  Future<List<Map<String, double>>?> get(String routeKey) async {
    await _ensureLoaded();
    return _mem[routeKey];
  }

  Future<void> put(String routeKey, List<Map<String, double>> polyline) async {
    if (polyline.isEmpty) return;
    await _ensureLoaded();
    // Re-insert at the end to mark as most-recent.
    _mem.remove(routeKey);
    _mem[routeKey] = polyline;
    while (_mem.length > _kMaxRoutes) {
      _mem.remove(_mem.keys.first);
    }
    await _persist();
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Store as compact [[lat,lng],...] arrays to keep the blob small.
      final out = _mem.map(
        (key, pts) =>
            MapEntry(key, pts.map((p) => [p['lat'], p['lng']]).toList()),
      );
      await prefs.setString(_kKey, json.encode(out));
    } catch (_) {
      // Best effort; an unwritable cache must never break trip loading.
    }
  }
}
