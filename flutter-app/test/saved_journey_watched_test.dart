import 'package:besser_bahn/models/journey.dart';
import 'package:besser_bahn/models/library_models.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _journeyJson() => {
  'legs': [
    {
      'origin': {'id': '8000199', 'name': 'Kiel Hbf'},
      'destination': {'id': '8002549', 'name': 'Hamburg Hbf'},
      'plannedDeparture': '2026-07-15T10:00:00.000',
    },
  ],
};

SavedJourney _saved({bool? watched}) {
  final j = SavedJourney(
    journey: Journey.fromJson(_journeyJson()),
    savedAtMs: 42,
  );
  return watched == null ? j : j.copyWith(watched: watched);
}

void main() {
  group('SavedJourney.watched — per-trip live tracking (#11, point 2)', () {
    test('a newly saved trip is watched by default', () {
      expect(_saved().watched, isTrue);
    });

    test('MIGRATION: a trip saved before this existed stays watched', () {
      // The old on-disk shape had no `watched` key. Defaulting it to false
      // would silently switch off alerts for people already relying on them.
      final old = SavedJourney.fromJson({
        'journey': _journeyJson(),
        'savedAtMs': 123,
      });
      expect(
        old.watched,
        isTrue,
        reason: 'an update must not take alerts away silently',
      );
    });

    test('an explicit opt-out survives a round-trip to disk', () {
      final restored = SavedJourney.fromJson(_saved(watched: false).toJson());
      expect(
        restored.watched,
        isFalse,
        reason: 'switching tracking off must stick across a restart',
      );
    });

    test('an explicit opt-in survives a round-trip to disk', () {
      expect(
        SavedJourney.fromJson(_saved(watched: true).toJson()).watched,
        isTrue,
      );
    });

    test('copyWith(watched:) leaves identity and save time alone', () {
      final orig = _saved();
      final off = orig.copyWith(watched: false);
      expect(off.savedAtMs, 42);
      expect(off.key, orig.key, reason: 'the trip must not change identity');
    });
  });
}
