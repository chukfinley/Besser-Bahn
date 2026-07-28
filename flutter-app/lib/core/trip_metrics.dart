import 'package:latlong2/latlong.dart';

import '../models/journey.dart';

/// Per-trip metrics derived purely from a [Journey] — distance and the arrival
/// delay at the final stop. Used by the lifetime travel-stats accumulator and
/// anywhere a single trip's numbers are shown.
///
/// Distance is the great-circle sum of each transit leg's origin→destination,
/// scaled by [_railDetourFactor] because tracks curve and detour around terrain
/// — a straight line undercounts real rail kilometres by ~15-25 %. It's an
/// honest estimate, not the billed tariff distance (which needs DB's route
/// graph / login). Legs missing coordinates are skipped, so the result is a
/// lower bound rather than wrong.
class TripMetrics {
  /// "On time" cut-off (DB counts < 6 min late as pünktlich).
  static const int onTimeThresholdMinutes = 6;

  static const double _railDetourFactor = 1.2;
  static const Distance _geo = Distance();

  /// Estimated travelled distance for [journey], in kilometres.
  static double distanceKm(Journey journey) {
    var metres = 0.0;
    for (final leg in journey.legs) {
      if (leg.isWalking) continue;
      final a = leg.origin, b = leg.destination;
      if (!a.hasLocation || !b.hasLocation) continue;
      metres += _geo.as(
        LengthUnit.Meter,
        LatLng(a.latitude!, a.longitude!),
        LatLng(b.latitude!, b.longitude!),
      );
    }
    return metres / 1000.0 * _railDetourFactor;
  }

  /// Arrival delay at the final destination in minutes (0 if early/unknown).
  static int finalArrivalDelayMinutes(Journey journey) {
    final last =
        journey.legs.where((l) => !l.isWalking).toList().lastOrNull;
    final d = last?.arrivalDelayMinutes ?? 0;
    return d > 0 ? d : 0;
  }

  /// "Origin → Destination" label for the whole trip — the key for
  /// "häufigste Strecken" in the Jahresrückblick (#71). Empty when either end
  /// is unknown.
  static String routeLabel(Journey journey) {
    final legs = journey.legs.where((l) => !l.isWalking).toList();
    final from = legs.firstOrNull?.origin.name ?? '';
    final to = legs.lastOrNull?.destination.name ?? '';
    if (from.isEmpty || to.isEmpty) return '';
    return '$from → $to';
  }

  /// The transit lines ridden on this trip (one entry per boarded leg), for
  /// "meistgenutzte Linien" (#71). Walking legs and unnamed lines are skipped.
  static List<String> linesUsed(Journey journey) {
    final out = <String>[];
    for (final leg in journey.legs) {
      if (leg.isWalking) continue;
      final name = leg.line?.displayName.trim() ?? '';
      if (name.isNotEmpty) out.add(name);
    }
    return out;
  }

  /// Transfers between two consecutive boarded legs (walking legs bridge, they
  /// aren't a transfer of their own).
  static int transferCount(Journey journey) {
    final ride = journey.legs.where((l) => !l.isWalking).length;
    return ride > 1 ? ride - 1 : 0;
  }

  /// Best-effort count of transfers that could NOT be made: the feeder's actual
  /// arrival landed after the onward train's actual departure (#71). Uses
  /// realtime times where present, so it only fires on a genuinely blown change,
  /// not on a tight-but-made one. A conservative lower bound.
  static int missedConnections(Journey journey) {
    final ride = journey.legs.where((l) => !l.isWalking).toList();
    var missed = 0;
    for (var i = 0; i + 1 < ride.length; i++) {
      final arr = ride[i].arrival;
      final dep = ride[i + 1].departure;
      if (arr != null && dep != null && arr.isAfter(dep)) missed++;
      if (ride[i + 1].cancelled) missed++;
    }
    return missed;
  }
}
