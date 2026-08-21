import 'package:besser_bahn/services/coach_sequence_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Which products the app spends a Wagenreihung request on (#33).
///
/// `S` used to be excluded with the note "S-Bahn hat keine Sequenz". Measured
/// against the real endpoint on 2026-07-16 (3 departures per network), that was
/// simply untrue — and the truth is per-NETWORK, not per-product:
///
///   served 3/3  Rhein-Neckar (Heidelberg), Rhein-Ruhr (Essen), Nürnberg,
///               Dresden — real cars with metre positions; the Rhein-Neckar
///               S-Bahn even comes back as coupled portions with different
///               destinations (S1 Homburg / S3 Germersheim)
///   served 0/3  Hamburg, Berlin, München, Stuttgart, Rhein-Main → 404
///
/// Where a network serves nothing the endpoint 404s and the app stays quiet,
/// exactly as it already does for a regional train's terminus. DB's own board
/// flag `wagenreihung: true` is NOT a shortcut here — München, Stuttgart and
/// Frankfurt set it and then 404.
void main() {
  group('sequenceKeyFor — which products have a Wagenreihung', () {
    test('S-Bahn is fetchable (#33)', () {
      final k = CoachSequenceService.sequenceKeyFor('S', '38154');
      expect(k, isNotNull);
      expect(k!.category, 'S');
      expect(k.number, 38154);
    });

    test('lower-case / padded product still resolves', () {
      expect(
        CoachSequenceService.sequenceKeyFor(' s ', ' 38154 ')?.category,
        'S',
      );
    });

    test('long-distance and regional keep working', () {
      for (final c in ['ICE', 'IC', 'EC', 'RE', 'RB', 'IRE']) {
        expect(
          CoachSequenceService.sequenceKeyFor(c, '1'),
          isNotNull,
          reason: '$c must stay fetchable',
        );
      }
    });

    test('bus/tram/U-Bahn have no sequence and are not fetched', () {
      for (final c in ['BUS', 'STR', 'U', 'TRAM']) {
        expect(
          CoachSequenceService.sequenceKeyFor(c, '1'),
          isNull,
          reason: '$c has no Wagenreihung — must not cost a request',
        );
      }
    });

    test('an unparseable train number is never fetched', () {
      // S-Bahn LINE labels ("S1") are not train numbers — asking with one would
      // be a guaranteed 404, so it must not even leave the device.
      expect(CoachSequenceService.sequenceKeyFor('S', ''), isNull);
      expect(CoachSequenceService.sequenceKeyFor('S', 'S1'), isNull);
    });
  });
}
