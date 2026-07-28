import 'package:besser_bahn/core/trip_metrics.dart';
import 'package:besser_bahn/models/departure.dart' show TransitLine;
import 'package:besser_bahn/models/journey.dart';
import 'package:besser_bahn/models/station.dart';
import 'package:besser_bahn/models/travel_stats.dart';
import 'package:flutter_test/flutter_test.dart';

Station _st(String name) => Station(id: name, name: name);

TransitLine _line(String name) => TransitLine(
    name: name, fahrtNr: '1', productName: name, product: 'regional');

JourneyLeg _leg(String from, String to, String line,
        {DateTime? arr, DateTime? dep, bool cancelled = false}) =>
    JourneyLeg(
      origin: _st(from),
      destination: _st(to),
      line: _line(line),
      arrival: arr,
      departure: dep,
      cancelled: cancelled,
    );

Journey _journey(List<JourneyLeg> legs) => Journey(legs: legs);

void main() {
  group('TripMetrics year-review helpers (#71)', () {
    test('routeLabel is first origin to last destination', () {
      final j = _journey([_leg('A', 'B', 'RE1'), _leg('B', 'C', 'RE2')]);
      expect(TripMetrics.routeLabel(j), 'A → C');
    });

    test('linesUsed lists each boarded leg', () {
      final j = _journey([_leg('A', 'B', 'RE1'), _leg('B', 'C', 'RE1')]);
      expect(TripMetrics.linesUsed(j), ['RE1', 'RE1']);
    });

    test('transferCount is boarded legs minus one', () {
      expect(
          TripMetrics.transferCount(
              _journey([_leg('A', 'B', 'RE1'), _leg('B', 'C', 'RE2')])),
          1);
      expect(TripMetrics.transferCount(_journey([_leg('A', 'B', 'RE1')])), 0);
    });

    test('missedConnections fires when feeder arrives after onward departs', () {
      final t0 = DateTime(2026, 8, 1, 9, 0);
      final made = _journey([
        _leg('A', 'B', 'RE1', arr: t0),
        _leg('B', 'C', 'RE2', dep: t0.add(const Duration(minutes: 5))),
      ]);
      expect(TripMetrics.missedConnections(made), 0);

      final missed = _journey([
        _leg('A', 'B', 'RE1', arr: t0.add(const Duration(minutes: 10))),
        _leg('B', 'C', 'RE2', dep: t0),
      ]);
      expect(TripMetrics.missedConnections(missed), 1);
    });

    test('a cancelled onward leg counts as missed', () {
      final missed = _journey([
        _leg('A', 'B', 'RE1'),
        _leg('B', 'C', 'RE2', cancelled: true),
      ]);
      expect(TripMetrics.missedConnections(missed), 1);
    });
  });

  group('TravelStats aggregates (#71)', () {
    test('topRoutes / topLines rank by frequency', () {
      const s = TravelStats(
        tripCount: 5,
        routeCounts: {'A → B': 3, 'C → D': 1},
        lineCounts: {'RE1': 4, 'ICE 5': 2},
      );
      expect(s.topRoutes().first.key, 'A → B');
      expect(s.topRoutes().first.value, 3);
      expect(s.topLines().first.key, 'RE1');
    });

    test('connectionsMade never negative and complements missed', () {
      const s = TravelStats(
          tripCount: 2, connectionsTotal: 3, connectionsMissed: 1);
      expect(s.connectionsMade, 2);
      const bad = TravelStats(
          tripCount: 1, connectionsTotal: 0, connectionsMissed: 2);
      expect(bad.connectionsMade, 0);
    });

    test('new fields round-trip through json', () {
      const s = TravelStats(
        tripCount: 1,
        routeCounts: {'A → B': 2},
        lineCounts: {'RE1': 2},
        connectionsTotal: 1,
        connectionsMissed: 1,
      );
      final back = TravelStats.fromJson(s.toJson());
      expect(back.routeCounts, {'A → B': 2});
      expect(back.lineCounts, {'RE1': 2});
      expect(back.connectionsTotal, 1);
      expect(back.connectionsMissed, 1);
    });

    test('old json without the new fields loads with empty defaults', () {
      final back = TravelStats.fromJson({'tripCount': 3, 'totalKm': 100.0});
      expect(back.routeCounts, isEmpty);
      expect(back.connectionsTotal, 0);
      expect(back.tripCount, 3);
    });
  });
}
