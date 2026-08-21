import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/trip_cache.dart';

final tripCacheProvider = Provider<TripCache>((ref) {
  return TripCache();
});
