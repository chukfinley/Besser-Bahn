import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/station.dart';
import '../utils/geo_query.dart';
import 'service_providers.dart';

/// One search answer, tagged with the query it answers.
///
/// Without the tag the suggestion list showed whatever came back last: type a
/// new term and the old results stayed on screen (and a slow request for an
/// earlier term could land *after* a fast one and overwrite it), so the list
/// said something entirely different from what was in the field. Consumers
/// compare [query] against the current text and only render a match.
class StationSearchResult {
  final String query;
  final List<Station> stations;

  /// Set when the results are stops near a pasted coordinate rather than name
  /// matches — lets the field explain where the list came from.
  final GeoQuery? geo;

  const StationSearchResult({
    required this.query,
    required this.stations,
    this.geo,
  });

  static const empty = StationSearchResult(query: '', stations: []);

  bool matches(String text) => query == text.trim();
}

/// Debounced station/address search provider.
///
/// Riverpod 3 dropped the separate `AutoDisposeAsyncNotifier` base class — a
/// plain [AsyncNotifier] is used for both, with auto-dispose selected on the
/// provider (`AsyncNotifierProvider.autoDispose`).
class StationSearchNotifier extends AsyncNotifier<StationSearchResult> {
  Timer? _debounce;

  /// Counts issued searches; a reply only lands if it is still the newest one.
  int _generation = 0;

  /// Restrict results to real stops (EVA required downstream). Set by the
  /// field that owns the query.
  bool stopsOnly = false;

  @override
  Future<StationSearchResult> build() async {
    // The field this provider serves is auto-disposed with its overlay — a
    // debounce still ticking then would write to a dead notifier.
    ref.onDispose(() => _debounce?.cancel());
    return StationSearchResult.empty;
  }

  void search(String rawQuery) {
    _debounce?.cancel();
    final query = rawQuery.trim();
    final gen = ++_generation;

    // A coordinate or map link → offer the nearest stops instead of searching
    // for a station literally named "53.4, 14.5" (#11). Useful exactly where
    // the normal search gives up: a place with no address or stop name.
    final geo = parseGeoQuery(query);
    if (query.length < 2 && geo == null) {
      state = AsyncData(StationSearchResult(query: query, stations: const []));
      return;
    }
    // Drop the previous answer right away — it belongs to the old query, and
    // showing it under the new text is the bug this guards.
    state = const AsyncLoading();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final hafas = ref.read(hafasServiceProvider);
        final stations = geo != null
            ? await hafas.nearbyStations(
                latitude: geo.latitude,
                longitude: geo.longitude,
              )
            : await hafas.searchStations(query, stopsOnly: stopsOnly);
        if (gen != _generation || !ref.mounted) return; // a newer query won
        state = AsyncData(
            StationSearchResult(query: query, stations: stations, geo: geo));
      } catch (e) {
        if (gen != _generation || !ref.mounted) return;
        state = AsyncError(e, StackTrace.current);
      }
    });
  }

  void clear() {
    _debounce?.cancel();
    _generation++;
    state = const AsyncData(StationSearchResult.empty);
  }
}

final stationSearchProvider = AsyncNotifierProvider.autoDispose<
    StationSearchNotifier, StationSearchResult>(StationSearchNotifier.new);
