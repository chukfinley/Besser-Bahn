import 'package:besser_bahn/models/journey.dart';
import 'package:besser_bahn/models/station.dart';
import 'package:besser_bahn/utils/arrival_buffer.dart';
import 'package:flutter_test/flutter_test.dart';

/// The rider's own case: be at the dentist by 09:48. DB's arrival search answers
/// with the tightest connection that makes it (09:39), which is a correct answer
/// and a poor plan — these tests are about judging every connection by the slack
/// it leaves instead.

const _selent =
    Station(id: '8005292', name: 'Selent', locationId: 'A=1@L=8005292@');
const _kiel =
    Station(id: '8000199', name: 'Kiel Hbf', locationId: 'A=1@L=8000199@');

final _deadline = DateTime(2026, 7, 27, 9, 48);

Journey _journey({
  DateTime? arrival,
  DateTime? plannedArrival,
  DateTime? departure,
  bool cancelled = false,
}) =>
    Journey(
      legs: [
        JourneyLeg(
          origin: _selent,
          destination: _kiel,
          departure: departure ?? DateTime(2026, 7, 27, 8, 30),
          plannedDeparture: departure ?? DateTime(2026, 7, 27, 8, 30),
          arrival: arrival,
          plannedArrival: plannedArrival ?? arrival,
          cancelled: cancelled,
        ),
      ],
    );

/// Arrives at [h]:[m] on the appointment's day.
Journey _arrivesAt(int h, int m, {int? delayMinutes}) {
  final planned = DateTime(2026, 7, 27, h, m);
  return _journey(
    arrival: delayMinutes == null
        ? planned
        : planned.add(Duration(minutes: delayMinutes)),
    plannedArrival: planned,
  );
}

void main() {
  group('journeyBuffer', () {
    test('slack between arrival and the appointment', () {
      expect(journeyBuffer(_arrivesAt(9, 39), _deadline),
          const Duration(minutes: 9));
      expect(journeyBuffer(_arrivesAt(8, 39), _deadline),
          const Duration(hours: 1, minutes: 9));
    });

    test('arriving after the appointment is negative, not zero', () {
      final buffer = journeyBuffer(_arrivesAt(9, 55), _deadline)!;
      expect(buffer.isNegative, isTrue);
      expect(buffer.inMinutes, -7);
    });

    test('a delay eats the buffer — the live arrival is what counts', () {
      // Scheduled 09:39 (9 min of air), running 12 late → misses it.
      final buffer = journeyBuffer(_arrivesAt(9, 39, delayMinutes: 12), _deadline)!;
      expect(buffer.inMinutes, -3);
    });

    test('falls back to the planned arrival when there is no live one', () {
      final j = _journey(plannedArrival: DateTime(2026, 7, 27, 9, 18));
      expect(journeyBuffer(j, _deadline), const Duration(minutes: 30));
    });

    test('no arrival at all is unjudgeable, never "fine"', () {
      expect(journeyBuffer(_journey(), _deadline), isNull);
    });
  });

  group('bufferTone', () {
    test('DB\'s own answer to an arrival search looks tight', () {
      expect(bufferTone(const Duration(minutes: 9)), BufferTone.tight);
    });

    test('too late is its own tone', () {
      expect(bufferTone(const Duration(minutes: -1)), BufferTone.missed);
    });

    test('comfortable below the generous threshold, generous above', () {
      expect(bufferTone(const Duration(minutes: 30)), BufferTone.comfortable);
      expect(bufferTone(const Duration(minutes: 44)), BufferTone.comfortable);
      expect(bufferTone(const Duration(minutes: 45)), BufferTone.generous);
      expect(bufferTone(const Duration(hours: 2)), BufferTone.generous);
    });

    test('the rider\'s own minimum decides what counts as tight for them', () {
      // 20 minutes clears the default threshold but not a 30-minute wish.
      expect(bufferTone(const Duration(minutes: 20)), BufferTone.comfortable);
      expect(bufferTone(const Duration(minutes: 20), minMinutes: 30),
          BufferTone.tight);
      expect(bufferTone(const Duration(minutes: 30), minMinutes: 30),
          BufferTone.comfortable);
    });
  });

  group('formatting', () {
    test('minutes below an hour, h+mm above', () {
      expect(formatBuffer(const Duration(minutes: 9)), '9 min');
      expect(formatBuffer(const Duration(minutes: 59)), '59 min');
      expect(formatBuffer(const Duration(minutes: 69)), '1 h 09');
      expect(formatBuffer(const Duration(hours: 2, minutes: 30)), '2 h 30');
    });

    test('being late reads as late, with a real minus sign', () {
      expect(formatBuffer(const Duration(minutes: -7)), '−7 min');
      expect(bufferLabel(const Duration(minutes: -7)), '−7 min zu spät');
      expect(bufferLabel(const Duration(minutes: 9)), '9 min Puffer');
    });
  });

  group('withMinBuffer', () {
    final journeys = [
      _arrivesAt(7, 39), // 2 h 09
      _arrivesAt(8, 39), // 1 h 09
      _arrivesAt(9, 18), // 30 min
      _arrivesAt(9, 39), // 9 min
      _arrivesAt(9, 55), // too late
    ];

    test('"egal" keeps everything, including the ones that miss it', () {
      expect(withMinBuffer(journeys, _deadline, null).length, 5);
    });

    test('a minimum drops the tight ones and the late one', () {
      final kept = withMinBuffer(journeys, _deadline, 30);
      expect(kept.length, 3);
      expect(
        [for (final j in kept) j.arrival!.hour],
        [7, 8, 9],
      );
      expect(withMinBuffer(journeys, _deadline, 60).length, 2);
      expect(withMinBuffer(journeys, _deadline, 180), isEmpty);
    });

    test('exactly the minimum still qualifies', () {
      expect(withMinBuffer([_arrivesAt(9, 18)], _deadline, 30).length, 1);
    });

    test('a connection without an arrival is kept — the filter is the rider\'s, '
        'missing data is not', () {
      expect(withMinBuffer([_journey()], _deadline, 60).length, 1);
    });
  });

  group('sortedByBuffer', () {
    test('most slack first', () {
      final sorted = sortedByBuffer(
        [_arrivesAt(9, 39), _arrivesAt(7, 39), _arrivesAt(9, 18)],
        _deadline,
      );
      expect([for (final j in sorted) j.arrival!.hour], [7, 9, 9]);
      expect(sorted.first.arrival!.minute, 39);
      expect(sorted[1].arrival!.minute, 18);
    });

    test('unjudgeable connections go last and keep their order', () {
      final a = _journey();
      final b = _journey();
      final sorted = sortedByBuffer([a, _arrivesAt(9, 18), b], _deadline);
      expect(identical(sorted[1], a), isTrue);
      expect(identical(sorted[2], b), isTrue);
    });

    test('equal buffers hold their incoming order (stable)', () {
      final first = _arrivesAt(9, 18);
      final second = _arrivesAt(9, 18);
      final sorted = sortedByBuffer([first, second], _deadline);
      expect(identical(sorted.first, first), isTrue);
      expect(identical(sorted.last, second), isTrue);
    });
  });
}
