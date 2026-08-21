import 'dart:convert';

import 'package:besser_bahn/models/departure.dart' show TransitLine;
import 'package:besser_bahn/models/journey.dart';
import 'package:besser_bahn/models/purchased_split.dart';
import 'package:besser_bahn/models/station.dart';
import 'package:besser_bahn/models/travel_stats.dart';
import 'package:besser_bahn/utils/data_export.dart';
import 'package:flutter_test/flutter_test.dart';

Station _st(String name, {double? lat, double? lon}) =>
    Station(id: name, name: name, latitude: lat, longitude: lon);

JourneyLeg _leg(Station from, Station to) => JourneyLeg(
  origin: from,
  destination: to,
  line: TransitLine(
    name: 'RE1',
    fahrtNr: '1',
    productName: 'RE1',
    product: 'regional',
  ),
  departure: DateTime(2026, 8, 1, 9),
);

void main() {
  group('statsToCsv (#72)', () {
    test('has a summary block and escapes commas', () {
      const stats = TravelStats(
        tripCount: 3,
        totalKm: 123.45,
        onTimeCount: 2,
        routeCounts: {'A, B → C': 2},
      );
      final csv = statsToCsv(stats, const []);
      expect(csv, contains('Kennzahl,Wert'));
      expect(csv, contains('Reisen,3'));
      expect(csv, contains('Kilometer,123.5'));
      // A route label containing a comma must be quoted.
      expect(csv, contains('"A, B → C",2'));
    });

    test('lists purchased splits and a total', () {
      final splits = [
        PurchasedSplit(
          routeLabel: 'A → B',
          directPrice: 50,
          splitPrice: 30,
          purchasedAtMs: 0,
        ),
      ];
      final csv = statsToCsv(TravelStats.empty, splits);
      expect(csv, contains('A → B,50.00,30.00,20.00'));
      expect(csv, contains('Gesamt gespart,,,20.00'));
    });
  });

  group('journeysToGeoJson (#72)', () {
    test('one LineString per journey, lon/lat order, dupes collapsed', () {
      final j = Journey(
        legs: [
          _leg(_st('A', lat: 54.0, lon: 10.0), _st('B', lat: 53.5, lon: 10.5)),
          _leg(_st('B', lat: 53.5, lon: 10.5), _st('C', lat: 53.0, lon: 11.0)),
        ],
      );
      final geo = jsonDecode(journeysToGeoJson([j])) as Map<String, dynamic>;
      expect(geo['type'], 'FeatureCollection');
      final features = geo['features'] as List;
      expect(features.length, 1);
      final coords = features.first['geometry']['coordinates'] as List;
      // A,B,C — the repeated B is collapsed.
      expect(coords.length, 3);
      expect(coords.first, [10.0, 54.0]); // [lon, lat]
    });

    test('journeys without coordinates are skipped', () {
      final j = Journey(legs: [_leg(_st('A'), _st('B'))]);
      final geo = jsonDecode(journeysToGeoJson([j])) as Map<String, dynamic>;
      expect((geo['features'] as List), isEmpty);
    });
  });

  group('journeysToGpx (#72)', () {
    test('one trk per journey, lat/lon order, dupes collapsed', () {
      final j = Journey(
        legs: [
          _leg(_st('A', lat: 54.0, lon: 10.0), _st('B', lat: 53.5, lon: 10.5)),
          _leg(_st('B', lat: 53.5, lon: 10.5), _st('C', lat: 53.0, lon: 11.0)),
        ],
      );
      final gpx = journeysToGpx([j]);
      expect(gpx, startsWith('<?xml version="1.0" encoding="UTF-8"?>'));
      expect(gpx, contains('<gpx version="1.1"'));
      expect('<trk>'.allMatches(gpx).length, 1);
      // A,B,C — the repeated B is collapsed. GPX is lat/lon, not lon/lat.
      expect('<trkpt'.allMatches(gpx).length, 3);
      expect(gpx, contains('<trkpt lat="54.0" lon="10.0">'));
    });

    test('journeys without coordinates produce no track', () {
      final j = Journey(legs: [_leg(_st('A'), _st('B'))]);
      expect(journeysToGpx([j]), isNot(contains('<trk>')));
    });

    test('station names with XML metacharacters are escaped', () {
      final j = Journey(
        legs: [
          _leg(
            _st('A & <B>', lat: 54.0, lon: 10.0),
            _st('C', lat: 53.0, lon: 11.0),
          ),
        ],
      );
      final gpx = journeysToGpx([j]);
      expect(gpx, contains('&amp;'));
      expect(gpx, isNot(contains('<B>')));
    });
  });
}
