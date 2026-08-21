import 'package:besser_bahn/models/departure.dart' show TransitLine;
import 'package:besser_bahn/models/journey.dart';
import 'package:besser_bahn/models/station.dart';
import 'package:besser_bahn/models/trip.dart';
import 'package:besser_bahn/utils/split_stops.dart';
import 'package:flutter_test/flutter_test.dart';

/// The ICE 1234 of the report: Berlin → Braunschweig → … → Frankfurt. The rider
/// only travels Berlin Hbf → Braunschweig Hbf; everything from Hildesheim on is
/// the train carrying on without them.
const _run = [
  'Berlin Hbf',
  'Berlin-Spandau',
  'Wolfsburg Hbf',
  'Braunschweig Hbf',
  'Hildesheim Hbf',
  'Kassel-Wilhelmshöhe',
  'Frankfurt(Main)Hbf',
];

final _base = DateTime(2026, 7, 16, 10);

DateTime _at(int i) => _base.add(Duration(minutes: 30 * i));

Station _st(String name) => Station(id: 'eva-$name', name: name);

/// A run stop as `/mob/zuglauf/{id}` delivers it: planned + realtime times.
Stopover _tso(String name) {
  final i = _run.indexOf(name);
  return Stopover(
    stop: _st(name),
    plannedArrival: i == 0 ? null : _at(i),
    arrival: i == 0 ? null : _at(i),
    plannedDeparture: i == _run.length - 1 ? null : _at(i),
    departure: i == _run.length - 1 ? null : _at(i),
  );
}

LegStopover _lso(String name) =>
    LegStopover(stop: _st(name), departure: _at(_run.indexOf(name)));

Trip _trip(List<String> stops) => Trip(
  id: 'zuglauf-1',
  line: const TransitLine(
    name: 'ICE 1234',
    fahrtNr: '1234',
    productName: 'ICE',
    product: 'nationalExpress',
  ),
  direction: stops.last,
  origin: _st(stops.first),
  destination: _st(stops.last),
  stopovers: [for (final s in stops) _tso(s)],
);

JourneyLeg _leg(List<String> stops) => JourneyLeg(
  tripId: 'zuglauf-1',
  origin: _st(stops.first),
  destination: _st(stops.last),
  plannedDeparture: _at(_run.indexOf(stops.first)),
  departure: _at(_run.indexOf(stops.first)),
  plannedArrival: _at(_run.indexOf(stops.last)),
  arrival: _at(_run.indexOf(stops.last)),
  line: const TransitLine(
    name: 'ICE 1234',
    fahrtNr: '1234',
    productName: 'ICE',
    product: 'nationalExpress',
  ),
  stopovers: [for (final s in stops) _lso(s)],
);

List<String> _names(List<Map<String, dynamic>> stops) => [
  for (final s in stops) s['name'] as String,
];

void main() {
  group('the cached train run is cut to the ridden section (#22)', () {
    // Berlin → Braunschweig, on an ICE that carries on to Frankfurt.
    final ride = [
      'Berlin Hbf',
      'Berlin-Spandau',
      'Wolfsburg Hbf',
      'Braunschweig Hbf',
    ];

    test('candidates never run past the leg destination', () {
      final stops = splitStopsFromJourney(
        Journey(legs: [_leg(ride)]),
        tripFor: (_) => _trip(_run),
      );

      expect(_names(stops), ride);
      expect(_names(stops), isNot(contains('Hildesheim Hbf')));
      expect(_names(stops), isNot(contains('Frankfurt(Main)Hbf')));
    });

    test('boundaries are the leg endpoints, not the ends of the run', () {
      final stops = splitStopsFromJourney(
        Journey(legs: [_leg(ride)]),
        tripFor: (_) => _trip(_run),
      );

      final boundaries = [
        for (final s in stops)
          if (s['_boundary'] == true) s['name'] as String,
      ];
      expect(boundaries, ['Berlin Hbf', 'Braunschweig Hbf']);
    });

    test('the run is still used where it knows stops the search omitted', () {
      // Search halte = endpoints only; the run adds the two stops between.
      final leg = JourneyLeg(
        tripId: 'zuglauf-1',
        origin: _st('Berlin Hbf'),
        destination: _st('Braunschweig Hbf'),
        plannedDeparture: _at(0),
        departure: _at(0),
        plannedArrival: _at(3),
        arrival: _at(3),
        line: const TransitLine(
          name: 'ICE 1234',
          fahrtNr: '1234',
          productName: 'ICE',
          product: 'nationalExpress',
        ),
        stopovers: [_lso('Berlin Hbf'), _lso('Braunschweig Hbf')],
      );

      final stops = splitStopsFromJourney(
        Journey(legs: [leg]),
        tripFor: (_) => _trip(_run),
      );

      expect(_names(stops), ride);
    });

    test('an unlocatable leg end falls back to the leg\'s own stops', () {
      // Run under a different id space (no name/id overlap) → no board index.
      final foreign = Trip(
        id: 'zuglauf-1',
        line: const TransitLine(
          name: 'ICE 1234',
          fahrtNr: '1234',
          productName: 'ICE',
          product: 'nationalExpress',
        ),
        direction: 'Anderswo',
        origin: const Station(id: 'x1', name: 'Anderswo Hbf'),
        destination: const Station(id: 'x2', name: 'Sonstwo Hbf'),
        stopovers: const [
          Stopover(
            stop: Station(id: 'x1', name: 'Anderswo Hbf'),
          ),
          Stopover(
            stop: Station(id: 'x2', name: 'Sonstwo Hbf'),
          ),
        ],
      );

      final stops = splitStopsFromJourney(
        Journey(legs: [_leg(ride)]),
        tripFor: (_) => foreign,
      );

      expect(_names(stops), ride);
    });

    test(
      'tripStopsForLeg picks the right call on a run that repeats a stop',
      () {
        // Ring: A … B … A. The leg boards at the SECOND call at A.
        Stopover so(String name, int min) => Stopover(
          stop: _st(name),
          plannedDeparture: _base.add(Duration(minutes: min)),
          departure: _base.add(Duration(minutes: min)),
          plannedArrival: _base.add(Duration(minutes: min)),
          arrival: _base.add(Duration(minutes: min)),
        );
        final trip = Trip(
          id: 'ring',
          line: const TransitLine(
            name: 'S1',
            fahrtNr: '1',
            productName: 'S',
            product: 'suburban',
          ),
          direction: 'A',
          origin: _st('A'),
          destination: _st('A'),
          stopovers: [so('A', 0), so('B', 20), so('A', 40), so('C', 60)],
        );
        final leg = JourneyLeg(
          tripId: 'ring',
          origin: _st('A'),
          destination: _st('C'),
          plannedDeparture: _base.add(const Duration(minutes: 40)),
          departure: _base.add(const Duration(minutes: 40)),
          plannedArrival: _base.add(const Duration(minutes: 60)),
          arrival: _base.add(const Duration(minutes: 60)),
          line: const TransitLine(
            name: 'S1',
            fahrtNr: '1',
            productName: 'S',
            product: 'suburban',
          ),
          stopovers: const [],
        );

        final ride = tripStopsForLeg(trip, leg)!;
        expect([for (final s in ride) s.stop.name], ['A', 'C']);
      },
    );
  });

  group('the split candidates carry the connection\'s own trains', () {
    test('a leg fed from the trip cache still knows its product and train', () {
      final stops = splitStopsFromJourney(
        Journey(
          legs: [
            _leg([
              'Berlin Hbf',
              'Berlin-Spandau',
              'Wolfsburg Hbf',
              'Braunschweig Hbf',
            ]),
          ],
        ),
        tripFor: (_) => _trip(_run),
      );

      // An ICE section is never free on the Deutschlandticket (#13) …
      expect(isSegmentDTicketCovered(stops, 0, stops.length - 1), isFalse);
      // … and its prices must be tied to the train the rider is on.
      expect(segmentTrainNumbers(stops, 0, stops.length - 1), ['1234']);
    });
  });
}
