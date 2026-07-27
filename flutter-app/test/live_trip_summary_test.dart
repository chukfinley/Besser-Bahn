import 'package:besser_bahn/models/departure.dart' show TransitLine;
import 'package:besser_bahn/models/journey.dart';
import 'package:besser_bahn/models/station.dart';
import 'package:besser_bahn/utils/live_trip_summary.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Live Update's progress bar IS the journey: a segment per leg, a marker at
/// every change, and a position that matches the clock. These tests pin that
/// arithmetic — the Android side only draws what comes out of here.

const _selent =
    Station(id: '8005292', name: 'Selent', locationId: 'A=1@L=8005292@');
const _kiel =
    Station(id: '8000199', name: 'Kiel Hbf', locationId: 'A=1@L=8000199@');
const _praxis =
    Station(id: '625109', name: 'Prof.-Peters-Platz', locationId: 'A=1@L=1@');

DateTime _at(int h, int m) => DateTime(2026, 7, 27, h, m);

JourneyLeg _leg({
  required Station from,
  required Station to,
  required DateTime departure,
  required DateTime arrival,
  bool walking = false,
  int departureDelay = 0,
  int arrivalDelay = 0,
  bool cancelled = false,
  String line = 'Bus 310',
}) =>
    JourneyLeg(
      origin: from,
      destination: to,
      cancelled: cancelled,
      departure: departure,
      plannedDeparture: departure,
      arrival: arrival,
      plannedArrival: arrival,
      departureDelay: departureDelay * 60,
      arrivalDelay: arrivalDelay * 60,
      isWalking: walking,
      line: walking
          ? null
          : TransitLine(name: line, fahrtNr: '1', productName: 'Bus', product: 'bus'),
    );

/// The dentist trip: Bus 310 (33 min) → 5 min walk → Bus 22 (9 min).
Journey _journey({int delay310 = 0, int delay22 = 0}) => Journey(legs: [
      _leg(
        from: _selent,
        to: _kiel,
        departure: _at(9, 1),
        arrival: _at(9, 34),
        departureDelay: delay310,
        arrivalDelay: delay310,
      ),
      _leg(
        from: _kiel,
        to: _kiel,
        departure: _at(9, 34),
        arrival: _at(9, 39),
        walking: true,
      ),
      _leg(
        from: _kiel,
        to: _praxis,
        departure: _at(9, 39),
        arrival: _at(9, 48),
        line: 'Bus 22',
        departureDelay: delay22,
        arrivalDelay: delay22,
      ),
    ]);

void main() {
  group('the bar is the journey', () {
    test('one segment per train, the walk folded into the ride it feeds', () {
      final trip = summariseTrip(_journey(), _at(9, 10));

      // 33 min of Bus 310, then 5 min walk + 9 min of Bus 22 = 14.
      expect(trip.segments.map((s) => s.minutes).toList(), [33, 14]);
      expect(trip.totalMinutes, 47);
    });

    test('a marker at the change, none at the start', () {
      final trip = summariseTrip(_journey(), _at(9, 10));
      expect(trip.transferPoints, [33]);
    });

    test('progress follows the clock and never runs past the end', () {
      expect(summariseTrip(_journey(), _at(9, 1)).progressMinutes, 0);
      expect(summariseTrip(_journey(), _at(9, 20)).progressMinutes, 19);
      expect(summariseTrip(_journey(), _at(23, 0)).progressMinutes, 47,
          reason: 'clamped to the bar');
    });

    test('before departure the bar starts at zero, not negative', () {
      expect(summariseTrip(_journey(), _at(8, 30)).progressMinutes, 0);
    });
  });

  group('the colours say what state each leg is in', () {
    test('done, current, still ahead', () {
      final trip = summariseTrip(_journey(), _at(9, 40));
      expect(trip.segments.first.color, LiveTripColors.done);
      expect(trip.segments.last.color, LiveTripColors.current);
    });

    test('everything ahead is pending before the trip starts', () {
      final trip = summariseTrip(_journey(), _at(8, 30));
      expect(trip.segments.every((s) => s.color == LiveTripColors.pending),
          isTrue);
    });

    test('a late leg is coloured as late — the one thing worth shouting', () {
      final trip = summariseTrip(_journey(delay22: 6), _at(9, 40));
      expect(trip.segments.last.color, LiveTripColors.delayed);
      expect(trip.delayMinutes, 6);
    });

    test('a leg already behind us is done, late or not', () {
      final trip = summariseTrip(_journey(delay310: 4), _at(9, 45));
      expect(trip.segments.first.color, LiveTripColors.done,
          reason: 'its delay stopped mattering when it arrived');
    });
  });

  group('which train the rider is on', () {
    test('the one being ridden', () {
      expect(summariseTrip(_journey(), _at(9, 10)).currentLeg?.line?.name,
          'Bus 310');
      expect(summariseTrip(_journey(), _at(9, 44)).currentLeg?.line?.name,
          'Bus 22');
    });

    test('before departure: the one about to be boarded, with its delay', () {
      final trip = summariseTrip(_journey(delay310: 3), _at(8, 30));
      expect(trip.currentLeg?.line?.name, 'Bus 310');
      expect(trip.delayMinutes, 3,
          reason: 'standing on the platform, that is the number that matters');
    });

    test('the arrival is the journey\'s, not the leg\'s', () {
      expect(summariseTrip(_journey(), _at(9, 10)).arrival, _at(9, 48));
    });
  });

  group('when there is nothing to draw', () {
    test('an empty journey', () {
      final trip = summariseTrip(const Journey(legs: []), _at(9, 0));
      expect(trip.isEmpty, isTrue);
      expect(trip.progressMinutes, 0);
    });

    test('a journey without times cannot be drawn, and says so', () {
      final trip = summariseTrip(
        Journey(legs: [JourneyLeg(origin: _selent, destination: _kiel)]),
        _at(9, 0),
      );
      expect(trip.isEmpty, isTrue);
    });

    test('a finished trip is finished', () {
      expect(summariseTrip(_journey(), _at(10, 30)).finishedAt(_at(10, 30)),
          isTrue);
      expect(summariseTrip(_journey(), _at(9, 30)).finishedAt(_at(9, 30)),
          isFalse);
    });

    test('a zero-length leg still gets a visible segment', () {
      final trip = summariseTrip(
        Journey(legs: [
          _leg(from: _selent, to: _kiel, departure: _at(9, 0), arrival: _at(9, 0)),
          _leg(from: _kiel, to: _praxis, departure: _at(9, 0), arrival: _at(9, 20)),
        ]),
        _at(9, 5),
      );
      expect(trip.segments.first.minutes, 1,
          reason: 'a zero-wide segment would make the bar lie about its scale');
    });
  });

  group('a cancelled train', () {
    // The Live Update colours itself by meaning, not by ARGB: a cancellation is
    // the one state that earns the loudest treatment the platform has.
    test('is reported on the leg the rider is on', () {
      final trip = summariseTrip(
        Journey(legs: [
          _leg(
            from: _selent,
            to: _kiel,
            departure: _at(9, 1),
            arrival: _at(9, 34),
            cancelled: true,
          ),
        ]),
        _at(9, 10),
      );
      expect(trip.cancelled, isTrue);
    });

    test('a running train is not cancelled', () {
      expect(summariseTrip(_journey(), _at(9, 10)).cancelled, isFalse);
    });
  });
}
