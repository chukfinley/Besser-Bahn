import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:besser_bahn/core/osm_rail.dart';
import 'package:besser_bahn/core/platform_train.dart';
import 'package:besser_bahn/core/platform_train.dart' as pt;
import 'package:besser_bahn/models/coach_sequence.dart';
import 'package:besser_bahn/models/station_map.dart';
import 'package:besser_bahn/services/station_map_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

/// Perpendicular distance (metres) from [p] to the line through [a]–[b], in a
/// local equirectangular metre frame (fine over a single platform).
double _perpMetres(LatLng p, LatLng a, LatLng b) {
  const mlat = 111320.0;
  final mlon = 111320.0 * math.cos(a.latitude * math.pi / 180);
  math.Point<double> xy(LatLng q) =>
      math.Point(q.longitude * mlon, q.latitude * mlat);
  final pa = xy(a), pb = xy(b), pp = xy(p);
  final ex = pb.x - pa.x, ey = pb.y - pa.y;
  final len = math.sqrt(ex * ex + ey * ey);
  if (len < 1e-9) return 0;
  // |cross(b-a, p-a)| / |b-a|
  return ((pp.x - pa.x) * ey - (pp.y - pa.y) * ex).abs() / len;
}

/// Shortest distance (metres) from [p] to a polyline — each segment measured
/// as a real segment (clamped at its ends), not an infinite line.
double _distanceToPath(LatLng p, List<LatLng> path) {
  if (path.isEmpty) return double.infinity;
  if (path.length == 1) {
    return const Distance().as(LengthUnit.Meter, p, path.first);
  }
  const mlat = 111320.0;
  final mlon = 111320.0 * math.cos(path.first.latitude * math.pi / 180);
  math.Point<double> xy(LatLng q) =>
      math.Point(q.longitude * mlon, q.latitude * mlat);
  final pp = xy(p);
  var best = double.infinity;
  for (var i = 0; i + 1 < path.length; i++) {
    final a = xy(path[i]), b = xy(path[i + 1]);
    final ex = b.x - a.x, ey = b.y - a.y;
    final len2 = ex * ex + ey * ey;
    // Project p onto the segment, clamped to [0,1] so a point beyond an end
    // measures to that end rather than to the line's imaginary extension.
    final t = len2 < 1e-12
        ? 0.0
        : (((pp.x - a.x) * ex + (pp.y - a.y) * ey) / len2).clamp(0.0, 1.0);
    final dx = pp.x - (a.x + t * ex), dy = pp.y - (a.y + t * ey);
    best = math.min(best, math.sqrt(dx * dx + dy * dy));
  }
  return best;
}

// Deterministic parse test for the bahnhof.de station-map scrape, using a
// SAVED Kiel Hbf RSC fixture (no network) so it can't flake in CI.
//
// Kiel Hbf is the station that "showed no train" in the app: this proves the
// data IS in the payload (8 platforms / 16 sector cubes) and our parser pulls
// it out — so if a train fails to render there, the bug is in placement
// (platform_train), not the scrape. See station_map_live_test for the
// network round-trip.

/// The OSM rail a Gleis's train body rides, built exactly the way the app does
/// it (station_map_provider → osmRailForGleis, anchored on the cube side).
///
/// [pt.platformGenericBody] deliberately returns nothing without a trusted rail
/// — "no train" beats a train drawn beside the track — so a test that omits it
/// isn't testing the placement, it's testing that guard. These tests used to
/// call without one: two failed outright, and the third passed vacuously
/// because it skipped every empty body.
List<LatLng> _railFor(StationMap map, String fixture, String gleis) {
  final osm =
      json.decode(File('test/fixtures/$fixture').readAsStringSync())
          as Map<String, dynamic>;
  List<LatLng> pts(dynamic list) => [
    for (final q in (list as List))
      LatLng((q['lat'] as num).toDouble(), (q['lng'] as num).toDouble()),
  ];
  return osmRailForGleis(
    platforms: [
      for (final p in (osm['platforms'] as List))
        (ref: p['ref'] as String, pts: pts(p['pts'])),
    ],
    rails: [for (final r in (osm['rails'] as List)) pts(r['pts'])],
    gleis: gleis,
    cubeSide: platformCubeSide(map, gleis),
  );
}

void main() {
  test('parses Kiel Hbf RSC fixture: platforms, sector cubes, levels', () {
    final body = File('test/fixtures/kiel-hbf.rsc.txt').readAsStringSync();
    final map = parseStationMapBody('kiel-hbf', body);

    final cubes = map.pois.where((p) => p.isPlatformSector).length;

    // The numbers we verified by hand from the live payload.
    expect(map.platforms.length, 8, reason: 'PLATFORM POIs (Gleise)');
    expect(cubes, 16, reason: 'PLATFORM_SECTOR_CUBE POIs (A/B/C…)');
    expect(map.levels, contains('GROUND_FLOOR'));
    expect(map.center.latitude, closeTo(54.315, 0.05));
    expect(map.center.longitude, closeTo(10.132, 0.05));
    expect(map.pois, isNotEmpty);
  });

  test(
    'platformGenericBody draws a closed train body when no Wagenreihung',
    () {
      final body = File('test/fixtures/kiel-hbf.rsc.txt').readAsStringSync();
      final map = parseStationMapBody('kiel-hbf', body);

      // A Gleis that actually carries sector cubes on its platform island.
      final gleis = map.platforms
          .map((p) => pt.normalizeGleis(p.name))
          .firstWhere(
            (g) => pt.platformSectors(map, g).length >= 2,
            orElse: () => '',
          );
      expect(
        gleis,
        isNotEmpty,
        reason: 'expected a Gleis with ≥2 sector cubes',
      );

      // Without a Wagenreihung we still get a single closed polygon (a train
      // body), curved along the platform, sized to a realistic length — not a
      // bare line nor the whole platform.
      final outline = pt.platformGenericBody(
        map,
        gleis: gleis,
        lengthM: 140,
        osmRail: _railFor(map, 'kiel-osm.json', gleis),
      );
      expect(
        outline.length,
        greaterThanOrEqualTo(3),
        reason: 'generic body is a closed ring',
      );
    },
  );

  test('Kiel Hbf generic body centreline is essentially straight', () {
    final body = File('test/fixtures/kiel-hbf.rsc.txt').readAsStringSync();
    final map = parseStationMapBody('kiel-hbf', body);

    // Kiel is a terminus of parallel STRAIGHT platforms and has 0 lift/escalator
    // anchors, so its island resolution can mix cubes from several tracks. The
    // body must still come out straight (no phantom parabola bend).
    final gleis = map.platforms
        .map((p) => pt.normalizeGleis(p.name))
        .firstWhere(
          (g) => pt.platformSectors(map, g).length >= 2,
          orElse: () => '',
        );
    expect(gleis, isNotEmpty, reason: 'expected a Gleis with ≥2 sector cubes');

    final outline = pt.platformGenericBody(
      map,
      gleis: gleis,
      lengthM: 140,
      osmRail: _railFor(map, 'kiel-osm.json', gleis),
    );
    expect(outline.length, greaterThanOrEqualTo(3));

    // Chord between the two most-distant vertices (the body's long axis). On a
    // straight platform every vertex sits within ~half the body width (≈1.4 m,
    // plus a little for the rounded snouts) of that chord; a parabola bend
    // would push the mid vertices several metres off it. Allow ~4 m.
    const dist = Distance();
    var ai = 0, bi = 0;
    var best = -1.0;
    for (var i = 0; i < outline.length; i++) {
      for (var j = i + 1; j < outline.length; j++) {
        final d = dist.as(LengthUnit.Meter, outline[i], outline[j]);
        if (d > best) {
          best = d;
          ai = i;
          bi = j;
        }
      }
    }
    final a = outline[ai], b = outline[bi];
    var maxDev = 0.0;
    for (final p in outline) {
      maxDev = math.max(maxDev, _perpMetres(p, a, b));
    }
    expect(
      maxDev,
      lessThan(4.0),
      reason: 'Kiel platform is straight; body deviates $maxDev m from chord',
    );
  });

  test('Hamburg Hbf body rides the rail despite mis-assigned cubes', () {
    // Hamburg Hbf's bahnhof.de sector cubes are mis-assigned per letter
    // (measured: a single Abschnitt sits up to ~60 m off the platform line —
    // physically impossible). Connecting them would zig-zag the train.
    //
    // This test used to assert the body came out *straight*, from when there
    // was no OSM rail and we laid the train on a best-fit axis. Hamburg's
    // platforms are strongly curved, so with the real rail a straight body
    // would now be the bug: Gleis 11 bends ~9.5 m away from its own chord, and
    // that is the track. What still has to hold — and is what the cubes could
    // break — is that the body follows the RAIL: every vertex within half a
    // body width (~1.4 m) of it, plus a little for the rounded snouts.
    final body = File('test/fixtures/hamburg-hbf.rsc.txt').readAsStringSync();
    final map = parseStationMapBody('hamburg-hbf', body);
    final dirty = map.platforms
        .map((p) => pt.normalizeGleis(p.name))
        .where((g) => pt.platformSectors(map, g).length >= 2)
        .toList();
    expect(dirty, isNotEmpty);
    var checked = 0;
    for (final g in dirty) {
      final rail = _railFor(map, 'hamburg-osm.json', g);
      final outline = pt.platformGenericBody(
        map,
        gleis: g,
        lengthM: 200,
        osmRail: rail,
      );
      // Not every Gleis in the fixture has a recoverable rail; those draw no
      // train at all, which is intended and nothing to assert.
      if (outline.length < 3) continue;
      checked++;
      var maxOff = 0.0;
      for (final p in outline) {
        maxOff = math.max(maxOff, _distanceToPath(p, rail));
      }
      expect(
        maxOff,
        lessThan(4.0),
        reason:
            'Gleis $g body strays $maxOff m from its rail — the '
            'mis-assigned cubes are deforming it',
      );
    }
    // Without this the test passes by checking nothing — which is exactly how
    // it survived losing its rail: every body came back empty and the loop
    // skipped them all.
    expect(
      checked,
      greaterThan(0),
      reason: 'no Gleis produced a body — nothing was actually asserted',
    );
  });

  test('a Wagenreihung without a sector table still draws its cars (#33)', () {
    // The S-Bahn payload shape, measured 2026-07-16: of the networks the
    // vehicle-sequence endpoint serves, only Rhein-Neckar ships a sector table
    // — Essen, Nürnberg and Dresden send real cars with real metre positions
    // and `platform.sectors: []`, every car's `sector` null.
    //
    // Sector letters are what anchors DB's metre axis onto the track, so those
    // sequences can't be placed exactly. They must still draw (to scale, in
    // order, centred) rather than be fetched and thrown away — otherwise
    // admitting S-Bahnen buys three of four networks nothing.
    final body = File('test/fixtures/hamburg-hbf.rsc.txt').readAsStringSync();
    final map = parseStationMapBody('hamburg-hbf', body);
    final raw =
        json.decode(
              File(
                'test/fixtures/hamburg-wagenreihung.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;

    // Strip it down to what an Essen/Nürnberg/Dresden S-Bahn actually returns.
    final sectorless = <String, dynamic>{
      ...raw,
      'platform': {...(raw['platform'] as Map<String, dynamic>), 'sectors': []},
      'groups': [
        for (final g in (raw['groups'] as List))
          {
            ...(g as Map<String, dynamic>),
            'vehicles': [
              for (final v in (g['vehicles'] as List))
                {
                  ...(v as Map<String, dynamic>),
                  if (v['platformPosition'] != null)
                    'platformPosition': {
                      ...(v['platformPosition'] as Map<String, dynamic>),
                      'sector': null,
                    },
                },
            ],
          },
      ],
    };
    final cs = CoachSequence.fromJson(sectorless);
    expect(cs.platform.sectors, isEmpty, reason: 'fixture must be sectorless');
    expect(cs.allCoaches, isNotEmpty);

    final gleis = pt.normalizeGleis(cs.departurePlatform);
    final rail = _railFor(map, 'hamburg-osm.json', gleis);
    if (rail.length < 2) {
      markTestSkipped('Gleis $gleis has no recoverable rail in the fixture');
      return;
    }
    final cars = pt.platformTrainCars(map, gleis: gleis, cs: cs, osmRail: rail);
    expect(
      cars,
      isNotEmpty,
      reason:
          'sectorless Wagenreihung drew no cars — S-Bahnen would be '
          'fetched and then rendered as nothing',
    );
    for (final c in cars) {
      expect(
        c.outline.length,
        greaterThanOrEqualTo(3),
        reason: 'each car is a closed ring',
      );
    }
  });
}
