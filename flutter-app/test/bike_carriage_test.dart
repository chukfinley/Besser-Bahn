import 'package:besser_bahn/models/departure.dart' show TransitLine;
import 'package:besser_bahn/models/journey.dart';
import 'package:besser_bahn/models/station.dart';
import 'package:flutter_test/flutter_test.dart';

/// Bike rules per train and per connection (#68). The keys come from vendo's
/// `attributNotizen` — FB "begrenzt möglich", FR "reservierungspflichtig",
/// FS "Sperrzeiten beachten" — verified live on Kiel→Berlin.

JourneyLeg _leg(BikeCarriage bike, {bool walking = false}) => JourneyLeg(
      origin: Station(id: 'a', name: 'A'),
      destination: Station(id: 'b', name: 'B'),
      line: walking
          ? null
          : TransitLine(
              name: 'RE1',
              fahrtNr: '1',
              productName: 'RE1',
              product: 'regional'),
      isWalking: walking,
      bike: bike,
    );

void main() {
  group('BikeCarriage.fromKeys', () {
    test('reads the three bike codes and ignores the rest', () {
      final b = BikeCarriage.fromKeys(['BR', 'FR', 'RO', 'fs']);
      expect(b.reservationRequired, isTrue);
      expect(b.restrictedHours, isTrue, reason: 'lowercase key must count');
      expect(b.limited, isFalse);
    });

    test('no bike note is "unknown", not "forbidden"', () {
      final b = BikeCarriage.fromKeys(['BR', 'WLAN']);
      expect(b.isEmpty, isTrue);
      expect(b.label, isNull);
      expect(b.detail, isNull);
    });
  });

  group('wording', () {
    test('reservation wins the short label — it is the one that bites', () {
      const b = BikeCarriage(reservationRequired: true, limited: true);
      expect(b.label, 'Rad: Reservierung nötig');
      expect(b.detail, contains('reservierungspflichtig'));
      expect(b.detail, contains('begrenzt möglich'));
    });

    test('limited alone reads as limited', () {
      const b = BikeCarriage(limited: true);
      expect(b.label, 'Rad: begrenzt möglich');
    });
  });

  group('Journey.bike', () {
    test('takes the strictest rule across all trains', () {
      final j = Journey(legs: [
        _leg(const BikeCarriage(limited: true)),
        _leg(BikeCarriage.none, walking: true),
        _leg(const BikeCarriage(reservationRequired: true)),
      ]);
      expect(j.bike.reservationRequired, isTrue);
      expect(j.bike.limited, isTrue);
      expect(j.bike.label, 'Rad: Reservierung nötig');
    });

    test('a connection whose trains say nothing says nothing', () {
      final j = Journey(legs: [_leg(BikeCarriage.none)]);
      expect(j.bike.isEmpty, isTrue);
    });
  });
}
