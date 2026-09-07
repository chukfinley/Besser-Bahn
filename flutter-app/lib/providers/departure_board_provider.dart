import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/station.dart';
import '../models/departure.dart';
import 'service_providers.dart';

enum BoardMode { departures, arrivals }

class DepartureBoardState {
  final Station? station;
  final List<Departure> departures;
  final bool isLoading;
  final String? error;
  final BoardMode mode;
  final String? filterProduct; // null = all

  /// When the shown departures were last successfully fetched (silent refresh
  /// included). Null until the first successful load.
  final DateTime? lastUpdated;

  const DepartureBoardState({
    this.station,
    this.departures = const [],
    this.isLoading = false,
    this.error,
    this.mode = BoardMode.departures,
    this.filterProduct,
    this.lastUpdated,
  });

  DepartureBoardState copyWith({
    Station? station,
    List<Departure>? departures,
    bool? isLoading,
    String? error,
    BoardMode? mode,
    String? filterProduct,
    bool clearFilter = false,
    DateTime? lastUpdated,
  }) {
    return DepartureBoardState(
      station: station ?? this.station,
      departures: departures ?? this.departures,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      mode: mode ?? this.mode,
      filterProduct: clearFilter ? null : (filterProduct ?? this.filterProduct),
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }

  List<Departure> get filteredDepartures {
    if (filterProduct == null) return departures;
    return departures.where((d) => d.line.product == filterProduct).toList();
  }
}

class DepartureBoardNotifier extends Notifier<DepartureBoardState> {
  @override
  DepartureBoardState build() => const DepartureBoardState();

  void setStation(Station station) {
    state = state.copyWith(station: station);
    load();
  }

  void setMode(BoardMode mode) {
    state = state.copyWith(mode: mode);
    load();
  }

  void setFilter(String? product) {
    state = state.copyWith(
      filterProduct: product,
      clearFilter: product == null,
    );
  }

  Future<void> load() async {
    final station = state.station;
    if (station == null) return;

    state = state.copyWith(isLoading: true, error: null);

    try {
      final results = await _fetch(station);
      state = state.copyWith(
        departures: results,
        isLoading: false,
        lastUpdated: DateTime.now(),
      );
    } catch (e) {
      state = state.copyWith(error: 'Fehler: $e', isLoading: false);
    }
  }

  /// Background refresh: re-fetch the board WITHOUT a loading spinner and,
  /// crucially, keep the currently shown departures if the fetch fails (offline
  /// etc.). Used by the auto-refresh timer and pull-to-refresh so the screen
  /// quietly stays up to date and never blanks out.
  Future<void> refreshSilent() async {
    final station = state.station;
    if (station == null) return;
    try {
      final results = await _fetch(station);
      // Success also clears any stale error from a previous failed load.
      state = state.copyWith(departures: results, lastUpdated: DateTime.now());
    } catch (_) {
      // Offline / upstream hiccup → keep the old departures untouched.
    }
  }

  Future<List<Departure>> _fetch(Station station) async {
    final hafas = ref.read(hafasServiceProvider);
    final arrivals = state.mode == BoardMode.arrivals;
    final board = arrivals
        ? await hafas.getArrivals(station.id, duration: 120)
        : await hafas.getDepartures(station.id, duration: 120);
    // The board itself only names the final destination. The stops on the way
    // ("Über", the column every station display has) come from the IRIS plan —
    // one small request per hour instead of a `zuglauf` per row. Best effort:
    // if IRIS is unreachable the board is shown exactly as before.
    try {
      return await ref
          .read(irisServiceProvider)
          .withVia(board, station.id, arrivals: arrivals);
    } catch (_) {
      return board;
    }
  }
}

final departureBoardProvider =
    NotifierProvider<DepartureBoardNotifier, DepartureBoardState>(
      DepartureBoardNotifier.new,
    );
