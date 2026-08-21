import 'package:besser_bahn/models/station.dart';
import 'package:besser_bahn/models/trip.dart';
import 'package:besser_bahn/services/coach_sequence_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// What identifies ONE Wagenreihung (#32).
///
/// The rule comes from measuring the live vehicle-sequence endpoint on
/// 2026-07-16, not from DB's docs (there are none): the run is selected by
/// `date` + category + number + evaNumber, and `time` is ignored outright —
/// ICE 205 @ Köln Hbf answered byte-identically for every time from −12 h to
/// +12 h while `date` stayed the service date, and answered 404 as soon as
/// `date` moved a day.
///
/// The app derives `date` from the same DateTime it sends as `time`, so asking
/// with a LIVE time is harmless right up to the moment a delay pushes it past
/// midnight — then it silently asks for tomorrow's run and the Wagenreihung
/// vanishes exactly when the rider needs it.
Stopover stop({
  DateTime? plannedDeparture,
  DateTime? departure,
  DateTime? plannedArrival,
  DateTime? arrival,
}) => Stopover(
  stop: const Station(id: '8000207', name: 'Köln Hbf'),
  plannedDeparture: plannedDeparture,
  departure: departure,
  plannedArrival: plannedArrival,
  arrival: arrival,
);

void main() {
  group('Stopover.sequenceTime — the key must ride the SERVICE date (#32)', () {
    test('prefers the scheduled departure over the live one', () {
      final s = stop(
        plannedDeparture: DateTime(2026, 7, 16, 23, 50),
        departure: DateTime(2026, 7, 17, 0, 25), // +35 min, past midnight
      );
      expect(s.sequenceTime, DateTime(2026, 7, 16, 23, 50));
    });

    test('a delay across midnight does not move the service date', () {
      // The whole point: date is derived from this DateTime. A live time would
      // ask for the 17th's run of the same number — which 404s.
      final s = stop(
        plannedDeparture: DateTime(2026, 7, 16, 23, 50),
        departure: DateTime(2026, 7, 17, 0, 25),
      );
      expect(s.sequenceTime!.day, 16);
    });

    test('falls back to the live time for an unscheduled extra stop', () {
      final s = stop(departure: DateTime(2026, 7, 16, 12));
      expect(s.sequenceTime, DateTime(2026, 7, 16, 12));
    });

    test('uses the scheduled arrival at a terminus (no departure there)', () {
      final s = stop(
        plannedArrival: DateTime(2026, 7, 16, 23, 55),
        arrival: DateTime(2026, 7, 17, 0, 40),
      );
      expect(s.sequenceTime, DateTime(2026, 7, 16, 23, 55));
    });

    test('is null when the stop carries no time at all', () {
      expect(stop().sequenceTime, isNull);
    });
  });

  group('cacheKeyFor — one train at one stop is one key', () {
    test('planned and live times would be DIFFERENT keys', () {
      // Why every call site must agree on which time it asks with: otherwise a
      // delayed train is fetched twice and the offline copy is written under a
      // key the live path never reads back.
      String key(DateTime t) => CoachSequenceService.cacheKeyFor(
        category: 'ICE',
        number: 205,
        stationEva: '8000207',
        departureTime: t,
      );
      expect(
        key(DateTime.utc(2026, 7, 16, 20, 54)),
        isNot(key(DateTime.utc(2026, 7, 16, 21, 32))),
      );
    });

    test('the same instant in another zone is the same key', () {
      final utc = CoachSequenceService.cacheKeyFor(
        category: 'S',
        number: 38154,
        stationEva: '8000156',
        departureTime: DateTime.utc(2026, 7, 16, 18, 48),
      );
      final local = CoachSequenceService.cacheKeyFor(
        category: 'S',
        number: 38154,
        stationEva: '8000156',
        departureTime: DateTime.utc(2026, 7, 16, 18, 48).toLocal(),
      );
      expect(utc, local);
    });
  });
}
