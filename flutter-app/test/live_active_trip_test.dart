import 'package:besser_bahn/models/departure.dart' show TransitLine;
import 'package:besser_bahn/models/journey.dart';
import 'package:besser_bahn/models/library_models.dart';
import 'package:besser_bahn/models/station.dart';
import 'package:besser_bahn/providers/live_trip_provider.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime _at(int h, int m) => DateTime(2026, 8, 2, h, m);

SavedJourney _trip(
  String name,
  DateTime dep,
  DateTime arr, {
  bool watched = true,
}) => SavedJourney(
  journey: Journey(
    legs: [
      JourneyLeg(
        origin: Station(id: '$name-a', name: '$name-A'),
        destination: Station(id: '$name-b', name: '$name-B'),
        plannedDeparture: dep,
        departure: dep,
        plannedArrival: arr,
        arrival: arr,
        line: TransitLine(
          name: name,
          fahrtNr: '1',
          productName: 'RE',
          product: 'regional',
        ),
      ),
    ],
  ),
  savedAtMs: 0,
  watched: watched,
);

void main() {
  group('pickActiveTrip (#live-active)', () {
    test('two overlapping running trips → the one boarded most recently', () {
      final skipped = _trip('Hildesheim', _at(15, 44), _at(20, 16));
      final riding = _trip('Elze', _at(17, 59), _at(22, 16));
      final pick = LiveTripTracker.pickActiveTrip([
        skipped,
        riding,
      ], _at(18, 30));
      expect(
        pick?.journey.legs.first.line?.name,
        'Elze',
        reason: 'you are on the later-departed train, not the earlier one',
      );
    });

    test('a running trip beats one merely about to depart', () {
      final running = _trip('A', _at(17, 0), _at(19, 0));
      final soon = _trip('B', _at(18, 45), _at(20, 0)); // departs in 15 min
      final pick = LiveTripTracker.pickActiveTrip([soon, running], _at(18, 30));
      expect(pick?.journey.legs.first.line?.name, 'A');
    });

    test('nothing departed yet → the soonest upcoming', () {
      final later = _trip('Late', _at(19, 30), _at(21, 0));
      final sooner = _trip('Soon', _at(18, 45), _at(20, 0));
      final pick = LiveTripTracker.pickActiveTrip([later, sooner], _at(18, 30));
      expect(pick?.journey.legs.first.line?.name, 'Soon');
    });

    test('unwatched trips are ignored', () {
      final off = _trip('Off', _at(17, 0), _at(20, 0), watched: false);
      final on = _trip('On', _at(17, 30), _at(20, 30));
      expect(
        LiveTripTracker.pickActiveTrip([
          off,
          on,
        ], _at(18, 0))?.journey.legs.first.line?.name,
        'On',
      );
      expect(LiveTripTracker.pickActiveTrip([off], _at(18, 0)), isNull);
    });

    test('trips outside the window (finished / far future) are skipped', () {
      final done = _trip('Done', _at(10, 0), _at(12, 0));
      final farFuture = _trip('Far', _at(23, 0), _at(23, 59));
      expect(
        LiveTripTracker.pickActiveTrip([done, farFuture], _at(18, 0)),
        isNull,
      );
    });
  });
}
