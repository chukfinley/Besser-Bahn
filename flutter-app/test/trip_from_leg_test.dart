import 'package:besser_bahn/models/departure.dart' show TransitLine;
import 'package:besser_bahn/models/journey.dart';
import 'package:besser_bahn/models/station.dart';
import 'package:besser_bahn/models/trip.dart';
import 'package:flutter_test/flutter_test.dart';

Station _st(String name) => Station(id: name, name: name);

JourneyLeg _leg({
  List<LegStopover>? stopovers,
  bool isWalking = false,
  TransitLine? line = const TransitLine(
    name: 'ICE 844',
    fahrtNr: '844',
    productName: 'ICE',
    product: 'ICE',
  ),
}) => JourneyLeg(
  tripId: '2|#VN#1#ST#123',
  origin: _st('Berlin Hbf'),
  destination: _st('Köln Hbf'),
  line: line,
  direction: 'Köln Hbf',
  isWalking: isWalking,
  stopovers:
      stopovers ??
      [
        LegStopover(
          stop: _st('Berlin Hbf'),
          departure: DateTime(2026, 7, 14, 10, 0),
        ),
        LegStopover(
          stop: _st('Hannover Hbf'),
          arrival: DateTime(2026, 7, 14, 11, 38),
          departure: DateTime(2026, 7, 14, 11, 40),
          arrivalDelay: 3600,
          cancelled: true,
        ),
        LegStopover(
          stop: _st('Köln Hbf'),
          arrival: DateTime(2026, 7, 14, 13, 0),
        ),
      ],
);

void main() {
  group('Trip.fromLeg — degraded fallback when getTrip fails (#14)', () {
    test('carries over the stops the journey search already returned', () {
      final trip = Trip.fromLeg(_leg())!;

      expect(trip.stopovers.map((s) => s.stop.name), [
        'Berlin Hbf',
        'Hannover Hbf',
        'Köln Hbf',
      ]);
      expect(trip.line.name, 'ICE 844');
      expect(trip.direction, 'Köln Hbf');
      expect(trip.origin.name, 'Berlin Hbf');
      expect(trip.destination.name, 'Köln Hbf');
    });

    test('preserves times, delays and cancellations', () {
      final trip = Trip.fromLeg(_leg())!;
      final hannover = trip.stopovers[1];

      expect(hannover.arrival, DateTime(2026, 7, 14, 11, 38));
      expect(hannover.departure, DateTime(2026, 7, 14, 11, 40));
      expect(hannover.arrivalDelay, 3600);
      expect(
        hannover.cancelled,
        isTrue,
        reason: 'a dropped stop must survive the fallback',
      );
    });

    test('leaves platform/occupancy empty rather than inventing them', () {
      final trip = Trip.fromLeg(_leg())!;
      final s = trip.stopovers.first;

      expect(s.departurePlatform, isNull);
      expect(s.plannedDeparturePlatform, isNull);
      expect(s.occupancy, OccupancyLevel.unknown);
      expect(
        trip.polyline,
        isNull,
        reason: 'no track geometry without zuglauf',
      );
      // Nothing to compare → no phantom Gleiswechsel in the degraded view.
      expect(s.hasDeparturePlatformChange, isFalse);
    });

    test('returns null when there is nothing to render a timeline from', () {
      expect(Trip.fromLeg(_leg(stopovers: const [])), isNull);
      expect(Trip.fromLeg(_leg(isWalking: true)), isNull);
      expect(Trip.fromLeg(_leg(line: null)), isNull);
    });
  });
}
