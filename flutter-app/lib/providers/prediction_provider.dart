import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/journey.dart';
import '../models/journey_prediction.dart';
import 'service_providers.dart';

/// Stable, value-equal key for a [Journey] so identical connections share one
/// prediction request (and don't refetch on rebuild/scroll).
class PredictionRequest {
  final Journey journey;
  final String key;

  PredictionRequest(this.journey) : key = _keyFor(journey);

  static String _keyFor(Journey j) {
    final dep = j.plannedDeparture?.toIso8601String() ?? '';
    final trains = j.legs
        .where((l) => !l.isWalking)
        .map((l) => l.line?.fahrtNr ?? '')
        .join('-');
    return '$dep|$trains|${j.legs.length}';
  }

  @override
  bool operator ==(Object other) =>
      other is PredictionRequest && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

/// Lazily fetches the connection-reliability prediction for a journey. The
/// reliability model only makes sense for FUTURE departures — for a trip that
/// has already arrived, the realised delay is what counts and we can derive
/// it locally from the journey itself. Don't burn a network round-trip on a
/// past trip; just return null so the badge stays hidden.
final journeyPredictionProvider = FutureProvider.autoDispose
    .family<JourneyPrediction?, PredictionRequest>((ref, req) async {
      final arr = req.journey.plannedArrival ?? req.journey.arrival;
      if (arr != null && arr.isBefore(DateTime.now())) return null;
      return ref.read(predictionServiceProvider).predict(req.journey);
    });
