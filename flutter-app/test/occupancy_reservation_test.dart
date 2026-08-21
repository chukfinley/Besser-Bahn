import 'package:besser_bahn/models/journey.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OccupancyLevel.recommendsReservation (#64)', () {
    test('recommended only at high and very high load', () {
      expect(OccupancyLevel.unknown.recommendsReservation, isFalse);
      expect(OccupancyLevel.low.recommendsReservation, isFalse);
      expect(OccupancyLevel.medium.recommendsReservation, isFalse);
      expect(OccupancyLevel.high.recommendsReservation, isTrue);
      expect(OccupancyLevel.veryHigh.recommendsReservation, isTrue);
    });

    test('hint text is present exactly when recommended', () {
      for (final l in OccupancyLevel.values) {
        expect(
          l.reservationHint.isNotEmpty,
          l.recommendsReservation,
          reason: '$l',
        );
      }
      expect(
        OccupancyLevel.high.reservationHint,
        'Sitzplatzreservierung empfohlen',
      );
    });
  });
}
