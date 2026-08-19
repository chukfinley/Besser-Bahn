import 'package:flutter_test/flutter_test.dart';

import 'package:besser_bahn/core/journey_reliability.dart';
import 'package:besser_bahn/models/journey.dart';

Journey _journey({
  int transfers = 0,
  bool cancelled = false,
  bool partiallyCancelled = false,
  bool disrupted = false,
  int? transferBufferMinutes,
  int departureDelayMinutes = 0,
  bool platformChange = false,
}) {
  final legs = <Map<String, dynamic>>[
    {
      'origin': {'name': 'A', 'id': 'A'},
      'destination': {'name': 'B', 'id': 'B'},
      'departure': '2026-08-19T10:00:00Z',
      'arrival': '2026-08-19T10:30:00Z',
      'cancelled': cancelled,
      'departureDelay': departureDelayMinutes * 60,
      'departurePlatform': platformChange ? '2' : '1',
      'plannedDeparturePlatform': '1',
      'stopovers': partiallyCancelled
          ? [
              {
                'stop': {'name': 'X', 'id': 'X'},
                'cancelled': true,
              }
            ]
          : [],
      'disruptions': disrupted ? ['Streckenstörung'] : [],
    },
  ];

  for (var i = 0; i < transfers; i++) {
    legs.add({
      'origin': {'name': 'B', 'id': 'B'},
      'destination': {'name': 'C', 'id': 'C'},
      'departure': '2026-08-19T10:40:00Z',
      'arrival': '2026-08-19T11:10:00Z',
      'walking': true,
      if (transferBufferMinutes != null) ...{
        'walkingSeconds': 300,
        'transferAvailableSeconds': transferBufferMinutes * 60,
      },
    });
    legs.add({
      'origin': {'name': 'C', 'id': 'C'},
      'destination': {'name': 'D', 'id': 'D'},
      'departure': '2026-08-19T11:20:00Z',
      'arrival': '2026-08-19T12:00:00Z',
    });
  }

  return Journey.fromJson({'legs': legs});
}

void main() {
  group('JourneyReliabilityAnalyzer', () {
    test('gives a perfect score to a clean direct journey', () {
      final result = JourneyReliabilityAnalyzer.analyze(_journey());

      expect(result.score, 100);
      expect(result.level, JourneyReliabilityLevel.veryReliable);
      expect(result.reasons, isEmpty);
    });

    test('penalizes a cancelled leg heavily', () {
      final result = JourneyReliabilityAnalyzer.analyze(
        _journey(cancelled: true),
      );

      expect(result.score, 40);
      expect(result.level, JourneyReliabilityLevel.risky);
      expect(result.reasons, contains('Cancelled train'));
    });

    test('penalizes a partial cancellation', () {
      final result = JourneyReliabilityAnalyzer.analyze(
        _journey(partiallyCancelled: true),
      );

      expect(result.score, 70);
      expect(result.level, JourneyReliabilityLevel.moderate);
      expect(result.reasons, contains('Partial cancellation'));
    });

    test('penalizes a significant delay', () {
      final result = JourneyReliabilityAnalyzer.analyze(
        _journey(departureDelayMinutes: 12),
      );

      expect(result.score, 85);
      expect(result.level, JourneyReliabilityLevel.reliable);
      expect(result.reasons, contains('Significant delay'));
    });

    test('penalizes a short transfer buffer', () {
      final result = JourneyReliabilityAnalyzer.analyze(
        _journey(
          transfers: 1,
          transferBufferMinutes: 4,
        ),
      );

      expect(result.score, 75);
      expect(result.level, JourneyReliabilityLevel.reliable);
      expect(result.reasons, contains('Short transfer buffer'));
    });

    test('penalizes platform changes', () {
      final result = JourneyReliabilityAnalyzer.analyze(
        _journey(platformChange: true),
      );

      expect(result.score, 92);
      expect(result.level, JourneyReliabilityLevel.veryReliable);
      expect(result.reasons, contains('Platform change'));
    });

    test('clamps the final score to zero', () {
      final result = JourneyReliabilityAnalyzer.analyze(
        _journey(
          transfers: 3,
          cancelled: true,
          disrupted: true,
          departureDelayMinutes: 20,
          transferBufferMinutes: 2,
          platformChange: true,
        ),
      );

      expect(result.score, greaterThanOrEqualTo(0));
      expect(result.score, lessThanOrEqualTo(100));
    });
  });
}