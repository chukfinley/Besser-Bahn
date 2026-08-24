import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/seat_map.dart';
import '../models/trip.dart';
import 'service_providers.dart';

/// Immutable request for one train segment's seat map. Used as the family key,
/// so equal segments share the same cached future.
class SeatMapRequest {
  final String fahrtNr;
  final String abfahrtEva;
  final DateTime abfahrtZeit;
  final String ankunftEva;
  final DateTime ankunftZeit;
  final bool firstClass;

  const SeatMapRequest({
    required this.fahrtNr,
    required this.abfahrtEva,
    required this.abfahrtZeit,
    required this.ankunftEva,
    required this.ankunftZeit,
    this.firstClass = false,
  });

  /// Build a request spanning a whole train run from its [Trip]. Returns null
  /// when the run lacks the train number or boarding/alighting EVAs + times.
  static SeatMapRequest? fromTrip(Trip trip, {bool firstClass = false}) {
    final fahrtNr = trip.line.fahrtNr.trim();
    if (fahrtNr.isEmpty) return null;
    final stops = trip.stopovers;
    if (stops.length < 2) return null;
    final first = stops.first;
    final last = stops.last;
    final abEva = first.stop.id;
    final anEva = last.stop.id;
    final abZeit = first.plannedDeparture ?? first.departure;
    final anZeit = last.plannedArrival ?? last.arrival;
    if (abEva.isEmpty || anEva.isEmpty || abZeit == null || anZeit == null) {
      return null;
    }
    return SeatMapRequest(
      fahrtNr: fahrtNr,
      abfahrtEva: abEva,
      abfahrtZeit: abZeit,
      ankunftEva: anEva,
      ankunftZeit: anZeit,
      firstClass: firstClass,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SeatMapRequest &&
      other.fahrtNr == fahrtNr &&
      other.abfahrtEva == abfahrtEva &&
      other.abfahrtZeit == abfahrtZeit &&
      other.ankunftEva == ankunftEva &&
      other.ankunftZeit == ankunftZeit &&
      other.firstClass == firstClass;

  @override
  int get hashCode => Object.hash(
    fahrtNr,
    abfahrtEva,
    abfahrtZeit,
    ankunftEva,
    ankunftZeit,
    firstClass,
  );
}

/// Fetches the seat map for a segment and attaches every coach's layout.
/// Resolves to null when the train has no reservable seat plan.
final seatMapProvider = FutureProvider.family<SeatMap?, SeatMapRequest>((
  ref,
  req,
) async {
  final service = ref.watch(seatMapServiceProvider);
  // gsd reports free seats only for the requested class, so fetch BOTH and
  // merge — otherwise first-class seats always read as occupied (#89). The two
  // requests share the segment; only `klasse` differs.
  Future<SeatMap?> fetch(bool firstClass) => service.fetchSeatMap(
    fahrtNr: req.fahrtNr,
    abfahrtEva: req.abfahrtEva,
    abfahrtZeit: req.abfahrtZeit,
    ankunftEva: req.ankunftEva,
    ankunftZeit: req.ankunftZeit,
    firstClass: firstClass,
  );
  final results = await Future.wait([fetch(false), fetch(true)]);
  final second = results[0];
  final first = results[1];
  final SeatMap? map;
  if (second != null && first != null) {
    map = second.mergeFreedom(first);
  } else {
    map = second ?? first;
  }
  if (map == null) return null;
  return service.attachLayouts(map);
});
