import 'package:besser_bahn/models/journey.dart';
import 'package:besser_bahn/models/station.dart';
import 'package:besser_bahn/utils/stopover_plan.dart';
import 'package:flutter_test/flutter_test.dart';

/// Breaking a trip in two at a hub: the second leg is nailed to the appointment,
/// the first is free to be much earlier, and the gap between them is the point.

const _selent = Station(
  id: '8005292',
  name: 'Selent',
  locationId: 'A=1@L=8005292@',
);
const _kiel = Station(
  id: '8000199',
  name: 'Kiel Hbf',
  locationId: 'A=1@L=8000199@',
);
const _praxis = Station(
  id: '625109',
  name: 'Kiel Professor-Peters-Platz',
  locationId: 'A=1@L=1@',
);

final _deadline = DateTime(2026, 7, 27, 9, 48);

DateTime _at(int h, int m) => DateTime(2026, 7, 27, h, m);

Journey _leg({
  required Station from,
  required Station to,
  required DateTime departure,
  required DateTime arrival,
  bool cancelled = false,
  String? token,
}) => Journey(
  refreshToken:
      token ??
      '${departure.hour}${departure.minute}-${arrival.hour}${arrival.minute}',
  legs: [
    JourneyLeg(
      origin: from,
      destination: to,
      departure: departure,
      plannedDeparture: departure,
      arrival: arrival,
      plannedArrival: arrival,
      cancelled: cancelled,
    ),
  ],
);

/// Kiel Hbf → the practice, arriving [arrH]:[arrM].
Journey _second(
  int depH,
  int depM,
  int arrH,
  int arrM, {
  bool cancelled = false,
}) => _leg(
  from: _kiel,
  to: _praxis,
  departure: _at(depH, depM),
  arrival: _at(arrH, arrM),
  cancelled: cancelled,
);

/// Selent → Kiel Hbf, arriving [arrH]:[arrM].
Journey _first(
  int depH,
  int depM,
  int arrH,
  int arrM, {
  bool cancelled = false,
}) => _leg(
  from: _selent,
  to: _kiel,
  departure: _at(depH, depM),
  arrival: _at(arrH, arrM),
  cancelled: cancelled,
);

void main() {
  group('latestArrivingBy — the leg nailed to the appointment', () {
    test('the latest departure that still gets there in time', () {
      final chosen = latestArrivingBy([
        _second(9, 0, 9, 12),
        _second(9, 30, 9, 42), // latest that makes 09:48
        _second(9, 45, 9, 57), // too late
      ], _deadline);

      expect(chosen, isNotNull);
      expect(chosen!.departure, _at(9, 30));
    });

    test('arriving exactly on the deadline counts as making it', () {
      final chosen = latestArrivingBy([_second(9, 36, 9, 48)], _deadline);
      expect(chosen?.departure, _at(9, 36));
    });

    test('nothing makes it → no plan, rather than a guess', () {
      expect(latestArrivingBy([_second(9, 45, 9, 57)], _deadline), isNull);
      expect(latestArrivingBy(const [], _deadline), isNull);
    });

    test('a cancelled leg is never the anchor', () {
      final chosen = latestArrivingBy([
        _second(9, 0, 9, 12),
        _second(9, 30, 9, 42, cancelled: true),
      ], _deadline);

      expect(chosen!.departure, _at(9, 0));
    });

    test('same departure → the one that arrives later keeps its own slack', () {
      final chosen = latestArrivingBy([
        _second(9, 20, 9, 30),
        _second(9, 20, 9, 44),
      ], _deadline);

      expect(chosen!.arrival, _at(9, 44));
    });

    test('a connection missing a time is skipped, not treated as 00:00', () {
      final noArrival = Journey(
        legs: [
          JourneyLeg(
            origin: _kiel,
            destination: _praxis,
            departure: _at(9, 40),
          ),
        ],
      );
      expect(latestArrivingBy([noArrival], _deadline), isNull);
    });
  });

  group('stayBetween', () {
    test('from getting in to the onward train leaving', () {
      expect(
        stayBetween(_first(7, 30, 8, 10), _second(9, 30, 9, 42)),
        const Duration(hours: 1, minutes: 20),
      );
    });

    test('null when either end has no time', () {
      final noArrival = Journey(
        legs: [
          JourneyLeg(
            origin: _selent,
            destination: _kiel,
            departure: _at(7, 30),
          ),
        ],
      );
      expect(stayBetween(noArrival, _second(9, 30, 9, 42)), isNull);
    });
  });

  group('firstLegOptions', () {
    final hubDeparture = _at(9, 30);
    final candidates = [
      _first(8, 50, 9, 25), // 5 min — too tight
      _first(8, 20, 8, 55), // 35 min
      _first(7, 20, 7, 55), // 1 h 35
      _first(9, 20, 9, 55), // arrives after the train has gone
    ];

    test(
      'only what leaves the wanted stay, and nothing that misses the train',
      () {
        final options = firstLegOptions(
          candidates,
          hubDeparture,
          minStayMinutes: 30,
        );

        expect(options.length, 2);
        expect([for (final o in options) o.arrival], [_at(7, 55), _at(8, 55)]);
      },
    );

    test(
      'chronological — earliest start on top, which is also the most time',
      () {
        final options = firstLegOptions(
          candidates,
          hubDeparture,
          minStayMinutes: 15,
        );
        expect(
          [for (final o in options) o.departure],
          [_at(7, 20), _at(8, 20)],
        );
      },
    );

    test('exactly the wanted stay qualifies', () {
      final options = firstLegOptions(
        [_first(8, 25, 9, 0)],
        hubDeparture,
        minStayMinutes: 30,
      );
      expect(options.length, 1);
    });

    test('a stay of 0 means "any train I can still catch"', () {
      final options = firstLegOptions(
        candidates,
        hubDeparture,
        minStayMinutes: 0,
      );
      // The 09:55 arrival is still out: the onward train left at 09:30.
      expect(options.length, 3);
    });

    test('cancelled candidates are dropped', () {
      final options = firstLegOptions(
        [_first(7, 20, 7, 55, cancelled: true), _first(8, 20, 8, 55)],
        hubDeparture,
        minStayMinutes: 30,
      );
      expect(options.length, 1);
      expect(options.single.departure, _at(8, 20));
    });

    test('nothing qualifies → empty, so the screen can say why', () {
      expect(
        firstLegOptions(candidates, hubDeparture, minStayMinutes: 300),
        isEmpty,
      );
    });
  });

  group('formatStay', () {
    test('minutes below an hour, h+mm above', () {
      expect(formatStay(const Duration(minutes: 45)), '45 min');
      expect(formatStay(const Duration(minutes: 60)), '1 h 00');
      expect(formatStay(const Duration(minutes: 80)), '1 h 20');
      expect(formatStay(const Duration(hours: 3)), '3 h 00');
    });
  });
}
