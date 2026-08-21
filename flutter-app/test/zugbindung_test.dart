import 'package:besser_bahn/providers/live_trip_provider.dart';
import 'package:flutter_test/flutter_test.dart';

/// A Sparpreis' Zugbindung falls away when the booked long-distance train is
/// cancelled or ≥20 min late — then the rider may switch trains. These pin that
/// rule (#zugbindung).

void main() {
  group('zugbindungAufgehoben', () {
    test('only long-distance trains carry a Zugbindung', () {
      expect(LiveTripTracker.isFernverkehr('nationalExpress'), isTrue); // ICE
      expect(LiveTripTracker.isFernverkehr('national'), isTrue); // IC/EC
      expect(LiveTripTracker.isFernverkehr('regional'), isFalse); // RE/RB
      expect(LiveTripTracker.isFernverkehr('suburban'), isFalse); // S
      expect(LiveTripTracker.isFernverkehr(null), isFalse);
    });

    test('lifted at ≥20 min late or on cancellation, on an ICE', () {
      expect(
        LiveTripTracker.zugbindungAufgehoben(
          product: 'nationalExpress',
          delaySeconds: 20 * 60,
        ),
        isTrue,
      );
      expect(
        LiveTripTracker.zugbindungAufgehoben(
          product: 'nationalExpress',
          cancelled: true,
        ),
        isTrue,
      );
    });

    test('not lifted below 20 min', () {
      expect(
        LiveTripTracker.zugbindungAufgehoben(
          product: 'nationalExpress',
          delaySeconds: 19 * 60,
        ),
        isFalse,
      );
    });

    test('a late regional train never lifts a Zugbindung (it has none)', () {
      expect(
        LiveTripTracker.zugbindungAufgehoben(
          product: 'regional',
          delaySeconds: 60 * 60,
          cancelled: true,
        ),
        isFalse,
      );
    });
  });
}
