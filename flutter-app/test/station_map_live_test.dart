import 'package:besser_bahn/services/station_map_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Live round-trip test: actually fetch Kiel Hbf from bahnhof.de and confirm
/// the whole pipeline (RSC fetch → isolate parse) works in the Flutter/Dart
/// runtime — the "does fetching work in Flutter" check.
///
/// Network-dependent by nature, so a connection failure SKIPS (not fails) —
/// run it on a connected machine to verify, and it won't break CI offline:
///   flutter test test/station_map_live_test.dart
void main() {
  test('fetches Kiel Hbf live and finds platforms + sector cubes', () async {
    final svc = StationMapService();
    try {
      final map = await svc.fetchByStationName('Kiel Hbf');
      final cubes = map.pois.where((p) => p.isPlatformSector).length;
      // ignore: avoid_print
      print(
        'Kiel live: ${map.platforms.length} platforms, $cubes cubes, '
        '${map.platformAnchors.length} anchors, ${map.levels.length} levels',
      );
      expect(map.platforms, isNotEmpty, reason: 'should find Gleise');
      expect(cubes, greaterThan(0), reason: 'should find A/B/C sector cubes');
    } on StationMapException catch (e) {
      // Timeout / host unreachable / not-found → skip instead of failing.
      markTestSkipped('Kiel live fetch unavailable: $e');
    } finally {
      svc.dispose();
    }
  }, timeout: const Timeout(Duration(seconds: 30)));
}
