import 'package:besser_bahn/core/stop_poles.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

/// Real coordinates from ZOB Kiel. OSM signs these poles A1…A5/B1…B3 (the same
/// codes on the real signs, and the codes DB puts in a leg's Gleis); DELFI
/// numbers the same poles 1/7/11 internally.
const _osmA4 = LatLng(54.31731, 10.13369);
const _osmA5 = LatLng(54.31748, 10.13383);
const _osmB3 = LatLng(54.31709, 10.13366);
const _delfi1 = LatLng(54.31729, 10.13371); // 2 m from OSM A4
const _delfi11 = LatLng(54.31747, 10.13384); // 2 m from OSM A5
const _delfi7 = LatLng(54.31709, 10.13371); // 4 m from OSM B3

StopPole _osm(String bay, LatLng at) =>
    StopPole(latLng: at, name: 'Kiel ZOB', bay: bay, shelter: true);
StopPole _delfi(String bay, LatLng at, List<String> dirs) =>
    StopPole(latLng: at, name: 'Kiel ZOB', bay: bay, directions: dirs);

void main() {
  group('#55 — merging the two sources', () {
    test('the same pole from both sources becomes one', () {
      final merged = mergePoles(
        [_osm('A4', _osmA4), _osm('A5', _osmA5), _osm('B3', _osmB3)],
        [
          _delfi('1', _delfi1, ['740 → Kiel ZOB']),
          _delfi('11', _delfi11, ['201 → Schönberg']),
          _delfi('7', _delfi7, ['743 → Gettorf']),
        ],
      );
      expect(merged, hasLength(3), reason: 'three physical poles, not six');
    });

    test('the signed code wins over DELFI\'s internal numbering', () {
      // The sign says A5, DELFI calls it 11 — the rider is looking for A5, and
      // that is also what DB puts in the leg.
      final merged = mergePoles(
        [_osm('A5', _osmA5)],
        [_delfi('11', _delfi11, ['201 → Schönberg'])],
      );
      expect(merged.single.bay, 'A5');
      expect(merged.single.directions, ['201 → Schönberg'],
          reason: 'the direction still comes from DELFI');
    });

    test('one bay, one dot — even when the two sources put it 22 m apart', () {
      // Kiel Hbf (the shared-link trip, Bus 310 → Bus 22): BOTH sources name
      // the bay here — DELFI's stop id is `de:01002:49076::B1`, the sign says
      // B1 — but they place it 22 m apart, and the map drew two dots labelled
      // "B1" for the rider to choose between.
      const osmB1 = LatLng(54.315671, 10.131436);
      const delfiB1 = LatLng(54.315870, 10.131493); // 22.5 m away
      const osmD2 = LatLng(54.315959, 10.131234);
      const delfiD2 = LatLng(54.315796, 10.131142); // 23.6 m from OSM's B1!

      final merged = mergePoles(
        [_osm('B1', osmB1), _osm('D2', osmD2)],
        [
          _delfi('B1', delfiB1, ['22 → Wik']),
          _delfi('D2', delfiD2, ['11 → Elmschenhagen']),
        ],
      );

      expect(merged, hasLength(2), reason: 'two bays, not four dots');
      final b1 = merged.firstWhere((p) => p.bay == 'B1');
      expect(b1.latLng, osmB1, reason: 'the sign is where the rider stands');
      expect(b1.directions, ['22 → Wik']);
    });

    test('distance never overrules a bay that matched by code', () {
      // The trap the distance rule alone walks into: DELFI's D2 is CLOSER to
      // OSM's B1 (23.6 m) than DELFI's own B1 is (22.5 m is closer still, but
      // the two are within metres of each other). Widening the radius to catch
      // B1 would swallow D2 into B1 — one bay off, on the wrong side of the
      // station.
      const osmB1 = LatLng(54.315671, 10.131436);
      const delfiD2 = LatLng(54.315796, 10.131142);

      final merged = mergePoles(
        [_osm('B1', osmB1), _osm('D2', const LatLng(54.315959, 10.131234))],
        [_delfi('D2', delfiD2, ['11 → Elmschenhagen'])],
      );

      final b1 = merged.firstWhere((p) => p.bay == 'B1');
      expect(b1.directions, isEmpty, reason: 'D2\'s buses are not B1\'s');
      expect(merged.firstWhere((p) => p.bay == 'D2').directions,
          ['11 → Elmschenhagen']);
    });

    test('a bay the signed source lists twice is still one pole', () {
      // OSM can carry the same bay as a stop node AND a platform node.
      final merged = mergePoles(
        [
          _osm('B1', const LatLng(54.315671, 10.131436)),
          _osm('B1', const LatLng(54.315680, 10.131500)),
        ],
        const [],
      );
      expect(merged, hasLength(1));
    });

    test('a pole only one source knows is kept', () {
      // OSM tags no bay at Wittenberger Passau; DELFI has both poles. Dropping
      // one would hide a pole the rider might be standing at.
      final merged = mergePoles(
        [StopPole(latLng: const LatLng(54.29029, 10.38406), name: 'B202')],
        [
          _delfi('1', const LatLng(54.29077, 10.38255), ['Kiel']),
          _delfi('2', const LatLng(54.2903, 10.38412), ['Schönberg']),
        ],
      );
      expect(merged, hasLength(3 - 1),
          reason: 'the OSM pole merges with DELFI Steig 2, Steig 1 is its own');
      expect(merged.map((p) => p.bay).toList(), ['1', '2']);
    });

    test('either source alone still yields a map', () {
      expect(mergePoles([_osm('A4', _osmA4)], const []), hasLength(1));
      expect(mergePoles(const [], [_delfi('1', _delfi1, const [])]),
          hasLength(1));
      expect(mergePoles(const [], const []), isEmpty);
    });

    test('poles sort by bay code, unlabelled last', () {
      final merged = mergePoles([
        _osm('B1', const LatLng(54.3165, 10.13322)),
        StopPole(latLng: const LatLng(54.3160, 10.1330), name: 'Kiel ZOB'),
        _osm('A1', const LatLng(54.31671, 10.13323)),
      ], const []);
      expect(merged.map((p) => p.bay).toList(), ['A1', 'B1', null]);
    });
  });

  group('#55 — finding the rider\'s own pole', () {
    final poles = mergePoles(
      [_osm('A4', _osmA4), _osm('A5', _osmA5), _osm('B3', _osmB3)],
      [_delfi('1', _delfi1, const ['740 → Kiel ZOB'])],
    );

    test('the leg\'s Gleis picks the pole with that code', () {
      // "Dein Einstieg: Gleis A4" → that exact pole, 90 m from A1.
      expect(poleForGleis(poles, 'A4')?.latLng, _osmA4);
      expect(poleForGleis(poles, 'A5')?.latLng, _osmA5);
    });

    test('spacing and case do not matter', () {
      expect(poleForGleis(poles, 'a4')?.bay, 'A4');
      expect(poleForGleis(poles, ' A 4 ')?.bay, 'A4');
    });

    test('an unknown code marks nothing rather than the nearest pole', () {
      // Marking the wrong pole is worse than marking none: the rider would
      // cross the road for it.
      expect(poleForGleis(poles, 'C9'), isNull);
      expect(poleForGleis(poles, null), isNull);
      expect(poleForGleis(poles, ''), isNull);
    });
  });

  test('metresBetween is right at pole distances', () {
    // A4 → A5 is one bay apart at ZOB Kiel.
    expect(metresBetween(_osmA4, _osmA5), closeTo(20, 4));
    expect(metresBetween(_osmA4, _delfi1), lessThan(kSamePoleMetres));
  });
}
