import 'package:besser_bahn/core/cache/cache_entry.dart';

import '../models/coach_sequence.dart';
import '../models/trip.dart';

class TripCache {
  final Map<String, CacheEntry<Trip>> _trips = {};

  final Map<String, CacheEntry<CoachSequence>> _coaches = {};

  Trip? getTrip(String id) {
    final entry = _trips[id];

    if (entry == null) {
      return null;
    }

    return entry.data;
  }

  void putTrip(String id, Trip trip) {
    _trips[id] = CacheEntry(data: trip, createdAt: DateTime.now());
  }

  CoachSequence? getCoach(String id) {
    return _coaches[id]?.data;
  }

  void putCoach(String id, CoachSequence value) {
    _coaches[id] = CacheEntry(data: value, createdAt: DateTime.now());
  }

  void clear() {
    _trips.clear();
    _coaches.clear();
  }
}
