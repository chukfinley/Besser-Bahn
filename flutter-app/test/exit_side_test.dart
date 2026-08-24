import 'package:besser_bahn/core/platform_train.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

/// Ausstiegsseite (#exit): which side the platform — and the doors you get off
/// through — sits on, in the direction of travel. Pure geometry: travel vector
/// × (track→platform) sign, in a local east/north frame. Facing north, east is
/// on your right; facing east, north is on your left.
void main() {
  const base = LatLng(50.0, 8.0);
  // ~111 m north and ~72 m east of `base` at 50° latitude.
  const north = LatLng(50.001, 8.0);
  const east = LatLng(50.0, 8.001);
  const west = LatLng(50.0, 7.999);
  const south = LatLng(49.999, 8.0);

  group('exitSideOf', () {
    test('travelling north, platform east ⇒ right', () {
      expect(
        exitSideOf(
          travelFrom: base,
          travelTo: north,
          track: base,
          platform: east,
        ),
        ExitSide.right,
      );
    });

    test('travelling north, platform west ⇒ left', () {
      expect(
        exitSideOf(
          travelFrom: base,
          travelTo: north,
          track: base,
          platform: west,
        ),
        ExitSide.left,
      );
    });

    test('travelling east, platform north ⇒ left', () {
      expect(
        exitSideOf(
          travelFrom: base,
          travelTo: east,
          track: base,
          platform: north,
        ),
        ExitSide.left,
      );
    });

    test('travelling east, platform south ⇒ right', () {
      expect(
        exitSideOf(
          travelFrom: base,
          travelTo: east,
          track: base,
          platform: south,
        ),
        ExitSide.right,
      );
    });

    test('reversing travel flips the side', () {
      final northbound = exitSideOf(
        travelFrom: base,
        travelTo: north,
        track: base,
        platform: east,
      );
      final southbound = exitSideOf(
        travelFrom: north,
        travelTo: base,
        track: base,
        platform: east,
      );
      expect(northbound, ExitSide.right);
      expect(southbound, ExitSide.left);
    });

    test('platform dead ahead or on the line ⇒ unknown', () {
      expect(
        exitSideOf(
          travelFrom: base,
          travelTo: north,
          track: base,
          platform: north,
        ),
        ExitSide.unknown,
      );
    });

    test('platform essentially on the track ⇒ unknown, not a coin toss', () {
      expect(
        exitSideOf(
          travelFrom: base,
          travelTo: north,
          track: base,
          platform: const LatLng(50.0, 8.0000001),
        ),
        ExitSide.unknown,
      );
    });
  });
}
