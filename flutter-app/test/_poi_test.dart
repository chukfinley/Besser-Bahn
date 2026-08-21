import 'dart:io';
import 'dart:math' as math;
import 'package:besser_bahn/core/platform_train.dart';
import 'package:besser_bahn/services/station_map_service.dart';
import 'package:flutter_test/flutter_test.dart';
void main() {
  test('platform POIs', () {
    final map = parseStationMapBody('hamburg-hbf',
        File('test/fixtures/hamburg-hbf.rsc.txt').readAsStringSync());
    final p7 = map.platforms.firstWhere((p) => normalizeGleis(p.name) == '7');
    final mlon = 111320.0 * math.cos(p7.latitude * math.pi / 180);
    double mx(double lon) => (lon - p7.longitude) * mlon;
    double my(double lat) => (lat - p7.latitude) * 111320.0;
    for (final p in map.platforms) {
      // ignore: avoid_print — this file is a hand-run probe, not an assertion test.
      print('Gleis ${p.name}: x=${mx(p.longitude).toStringAsFixed(0)} y=${my(p.latitude).toStringAsFixed(0)} level=${p.level}');
    }
  });
}
