import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_log.dart';
import '../core/cache/cache_entry.dart';
import '../core/journey_cache.dart';
import '../core/search_history_cache.dart';
import '../models/journey.dart';
import '../models/journey_search.dart';
import '../models/search_options.dart';
import '../models/station.dart';
import '../utils/arrival_buffer.dart';
import '../utils/journey_highlights.dart';
import 'prediction_provider.dart';
import 'service_providers.dart';
import 'settings_provider.dart';

enum JourneySortMode {
  departure,
  arrival,
  duration,
  transfers,
  reliability,

  /// Most slack before the appointment first.
  /// Only meaningful with arrival searches.
  buffer,
}

/// Transport categories supported by DB Vendo.
enum ProductCategory {
  fern('Fernverkehr', [
    'HOCHGESCHWINDIGKEITSZUEGE',
    'INTERCITYUNDEUROCITYZUEGE',
    'INTERREGIOUNDSCHNELLZUEGE',
  ]),
  regional('Regional', ['NAHVERKEHRSONSTIGEZUEGE', 'ANRUFPFLICHTIGEVERKEHRE']),
  sbahn('S-Bahn', ['SBAHNEN']),
  ubahn('U-Bahn', ['UBAHN']),
  tram('Tram', ['STRASSENBAHN']),
  bus('Bus & Fähre', ['BUSSE', 'SCHIFFE']);

  final String label;
  final List<String> vendoCodes;

  const ProductCategory(this.label, this.vendoCodes);

  static List<String> codesFor(Set<ProductCategory> cats) {
    if (cats.isEmpty || cats.length == ProductCategory.values.length) {
      return const ['ALL'];
    }

    return [for (final category in cats) ...category.vendoCodes];
  }
}

class JourneySearchState {
  final Station? from;
  final Station? to;

  final DateTime? dateTime;

  final bool isArrival;

  final JourneyResult? result;

  final bool isLoading;

  final String? error;

  final JourneySortMode sortMode;

  /// Selected transport modes.
  final Set<ProductCategory> products;

  /// Deutschlandticket filter.
  final bool onlyDeutschlandTicket;

  /// True when transfer profile was relaxed.
  final bool transferProfileRelaxed;

  /// Search constraints.
  final SearchOptions options;

  /// Minimum buffer before appointment.
  final int? minBufferMinutes;

  /// Changes every successful search.
  final int resultSerial;

  JourneySearchState({
    this.from,
    this.to,
    this.dateTime,
    this.isArrival = false,
    this.result,
    this.isLoading = false,
    this.error,
    this.sortMode = JourneySortMode.departure,
    this.onlyDeutschlandTicket = false,
    this.transferProfileRelaxed = false,
    this.options = const SearchOptions(),
    this.resultSerial = 0,
    this.minBufferMinutes,
    Set<ProductCategory>? products,
  }) : products = products ?? ProductCategory.values.toSet();

  bool get useArrival => dateTime != null && isArrival;

  DateTime? get deadline => useArrival ? dateTime : null;

  int get hiddenByBufferCount {
    final total = result?.journeys.length ?? 0;

    return total - sortedJourneys.length;
  }

  List<Journey> get sortedJourneys {
    if (result == null) {
      return [];
    }

    var journeys = result!.journeys.toList();

    final deadline = this.deadline;

    if (deadline != null) {
      journeys = withMinBuffer(journeys, deadline, minBufferMinutes);

      if (sortMode == JourneySortMode.buffer) {
        return sortedByBuffer(journeys, deadline);
      }
    }

    switch (sortMode) {
      case JourneySortMode.departure:
        journeys.sort(
          (a, b) => (a.departure ?? DateTime(0)).compareTo(
            b.departure ?? DateTime(0),
          ),
        );

      case JourneySortMode.arrival:
        journeys.sort(
          (a, b) =>
              (a.arrival ?? DateTime(0)).compareTo(b.arrival ?? DateTime(0)),
        );

      case JourneySortMode.duration:
        journeys.sort(
          (a, b) => (a.duration ?? Duration.zero).compareTo(
            b.duration ?? Duration.zero,
          ),
        );

      case JourneySortMode.transfers:
        journeys.sort((a, b) => a.transfers.compareTo(b.transfers));

      case JourneySortMode.reliability:
        journeys.sort(
          (a, b) => (a.departure ?? DateTime(0)).compareTo(
            b.departure ?? DateTime(0),
          ),
        );

      case JourneySortMode.buffer:
        journeys.sort(
          (a, b) => (a.departure ?? DateTime(0)).compareTo(
            b.departure ?? DateTime(0),
          ),
        );
    }

    return journeys;
  }

  JourneySearchState copyWith({
    Station? from,

    Station? to,

    DateTime? dateTime,

    bool? isArrival,

    JourneyResult? result,

    bool? isLoading,

    String? error,

    JourneySortMode? sortMode,

    Set<ProductCategory>? products,

    bool? onlyDeutschlandTicket,

    bool? transferProfileRelaxed,

    SearchOptions? options,

    int? resultSerial,

    int? minBufferMinutes,

    bool clearDateTime = false,

    bool clearMinBufferMinutes = false,

    bool clearError = false,
  }) {
    return JourneySearchState(
      from: from ?? this.from,

      to: to ?? this.to,

      dateTime: clearDateTime ? null : dateTime ?? this.dateTime,

      isArrival: isArrival ?? this.isArrival,

      result: result ?? this.result,

      isLoading: isLoading ?? this.isLoading,

      error: clearError ? null : error ?? this.error,

      sortMode: sortMode ?? this.sortMode,

      products: products ?? this.products,

      onlyDeutschlandTicket:
          onlyDeutschlandTicket ?? this.onlyDeutschlandTicket,

      transferProfileRelaxed:
          transferProfileRelaxed ?? this.transferProfileRelaxed,

      options: options ?? this.options,

      resultSerial: resultSerial ?? this.resultSerial,

      minBufferMinutes: clearMinBufferMinutes
          ? null
          : minBufferMinutes ?? this.minBufferMinutes,
    );
  }
}

class JourneySearchNotifier extends Notifier<JourneySearchState> {
  final SearchHistoryCache _historyCache = SearchHistoryCache();
  @override
  JourneySearchState build() => JourneySearchState();

  void setFrom(Station? station) => state = state.copyWith(from: station);

  void setTo(Station? station) => state = state.copyWith(to: station);

  void setDateTime(DateTime? dt) => state = state.copyWith(dateTime: dt);

  void setIsArrival(bool value) => state = state.copyWith(isArrival: value);

  void resetToNow() {
    state = state.copyWith(
      clearDateTime: true,
      isArrival: false,
      clearMinBufferMinutes: true,
    );
  }

  void setSortMode(JourneySortMode mode) {
    state = state.copyWith(sortMode: mode);
  }

  Future<void> setMinBufferMinutes(int? minutes) async {
    if (minutes == state.minBufferMinutes) return;

    state = state.copyWith(
      minBufferMinutes: minutes,
      clearMinBufferMinutes: minutes == null,
    );

    await _pageBackToBuffer();
  }

  static const int maxBufferPages = 3;

  Future<void> _pageBackToBuffer() async {
    if (state.deadline == null || state.minBufferMinutes == null) {
      return;
    }

    for (var i = 0; i < maxBufferPages; i++) {
      if (state.result == null) return;

      if (state.sortedJourneys.isNotEmpty) {
        return;
      }

      if (state.result!.earlierRef == null) {
        return;
      }

      final before = state.result!.journeys.length;

      await loadEarlier();

      if ((state.result?.journeys.length ?? 0) <= before) {
        return;
      }
    }
  }

  void toggleProduct(ProductCategory category) {
    final next = Set<ProductCategory>.from(state.products);

    if (!next.remove(category)) {
      next.add(category);
    }

    if (next.isEmpty) {
      next.addAll(ProductCategory.values);
    }

    state = state.copyWith(products: next);

    if (state.result != null) {
      search();
    }
  }

  void setAllProducts() {
    state = state.copyWith(products: ProductCategory.values.toSet());

    if (state.result != null) {
      search();
    }
  }

  void toggleOnlyDeutschlandTicket() {
    state = state.copyWith(onlyDeutschlandTicket: !state.onlyDeutschlandTicket);

    if (state.result != null) {
      search();
    }
  }

  void setOptions(SearchOptions options) {
    if (options == state.options) return;

    state = state.copyWith(options: options);

    if (state.result != null) {
      search();
    }
  }

  void swapStations() {
    state = state.copyWith(from: state.to, to: state.from);
  }

  Future<void> search({String? fromText, String? toText}) async {
    state = state.copyWith(isLoading: true, error: null);
    CacheEntry<JourneyResult>? cached;
    try {
      final hafas = ref.read(hafasServiceProvider);

      var from = state.from;
      var to = state.to;

      if (from == null && fromText != null && fromText.trim().length >= 2) {
        final results = await hafas.searchStations(fromText.trim());

        if (results.isNotEmpty) {
          from = results.first;

          state = state.copyWith(from: from);
          await _historyCache.add(
            JourneySearch(
              from: state.from?.name ?? '',
              to: state.to?.name ?? '',
              date: state.dateTime ?? DateTime.now(),
            ),
          );
        }
      }

      if (to == null && toText != null && toText.trim().length >= 2) {
        final results = await hafas.searchStations(toText.trim());

        if (results.isNotEmpty) {
          to = results.first;

          state = state.copyWith(to: to);
        }
      }

      if (from == null || to == null) {
        state = state.copyWith(
          isLoading: false,
          error: from == null && to == null
              ? 'Start und Ziel eingeben.'
              : from == null
              ? 'Startstation nicht gefunden.'
              : 'Zielstation nicht gefunden.',
        );

        return;
      }

      final cacheKey = JourneyCache.key(
        from: from.id,
        to: to.id,
        dateTime: state.dateTime ?? DateTime.now(),
        arrival: state.useArrival,
      );

      final cached = await JourneyCache.read(cacheKey);

      if (cached != null) {
        AppLog.log('loaded journey from offline cache', tag: 'offline');

        state = state.copyWith(result: cached.data, isLoading: false);

        // Cache hit:
        // keep cached result instead of blocking user
        // with another network request.
        return;
      }

      AppLog.log(
        'search ${from.name} (${from.id}) → '
        '${to.name} (${to.id})',
        tag: 'journey',
      );

      final vendo = ref.read(vendoServiceProvider);

      final settings = ref.read(settingsProvider);

      final party = settings.searchParty;

      final options = state.options;

      final fromProfile = options.minTransferMinutes == null;

      final minTransfer =
          options.minTransferMinutes ??
          settings.transferProfile.minTransferMinutes;

      Future<JourneyResult> run({int? minTransferMinutes}) {
        return vendo.searchJourneys(
          fromLocationId: from!.vendoLocationId,

          toLocationId: to!.vendoLocationId,

          dateTime: state.dateTime ?? DateTime.now(),

          isArrival: state.useArrival,

          firstClass: party.firstClass,

          reisende: party.toReisendeJson(),

          deutschlandTicket: party.deutschlandTicket,

          verkehrsmittel: ProductCategory.codesFor(state.products),

          nurDeutschlandTicketVerbindungen: state.onlyDeutschlandTicket,

          minTransferMinutes: minTransferMinutes,

          maxTransfers: options.maxTransfers,

          viaLocations: options.viaLocationsJson,
        );
      }

      var result = await run(minTransferMinutes: minTransfer);

      var relaxed = false;

      if (result.journeys.isEmpty && minTransfer != null && fromProfile) {
        result = await run();

        relaxed = result.journeys.isNotEmpty;
      }

      // NEW:
      // Save fresh result offline.
      await JourneyCache.write(cacheKey, result);

      state = state.copyWith(
        result: result,
        isLoading: false,
        transferProfileRelaxed: relaxed,
        resultSerial: state.resultSerial + 1,
      );
    } catch (e) {
      AppLog.log('search FAILED: $e', tag: 'journey');

      if (cached != null) {
        AppLog.log(
          'network failed — using stale journey cache',
          tag: 'offline',
        );

        state = state.copyWith(
          result: cached.data,
          isLoading: false,
          error: null,
        );

        return;
      }

      state = state.copyWith(error: 'Fehler: $e', isLoading: false);
    }
  }

  Future<void> loadEarlier() => _loadMore(earlier: true);

  Future<void> loadLater() => _loadMore(earlier: false);

  Future<void> _loadMore({required bool earlier}) async {
    final current = state.result;

    final token = earlier ? current?.earlierRef : current?.laterRef;

    if (token == null || state.from == null || state.to == null) {
      return;
    }

    state = state.copyWith(isLoading: true, error: null);

    try {
      final vendo = ref.read(vendoServiceProvider);

      final settings = ref.read(settingsProvider);

      final party = settings.searchParty;

      final options = state.options;

      final more = await vendo.searchJourneys(
        fromLocationId: state.from!.vendoLocationId,

        toLocationId: state.to!.vendoLocationId,

        dateTime: state.dateTime ?? DateTime.now(),

        isArrival: state.useArrival,

        context: token,

        firstClass: party.firstClass,

        reisende: party.toReisendeJson(),

        deutschlandTicket: party.deutschlandTicket,

        verkehrsmittel: ProductCategory.codesFor(state.products),

        nurDeutschlandTicketVerbindungen: state.onlyDeutschlandTicket,

        minTransferMinutes: state.transferProfileRelaxed
            ? null
            : options.minTransferMinutes ??
                  settings.transferProfile.minTransferMinutes,

        maxTransfers: options.maxTransfers,

        viaLocations: options.viaLocationsJson,
      );

      final existing = current?.journeys ?? const [];

      final seen = existing.map(_journeyKey).toSet();

      final fresh = more.journeys
          .where((j) => seen.add(_journeyKey(j)))
          .toList();

      final combined = JourneyResult(
        journeys: earlier ? [...fresh, ...existing] : [...existing, ...fresh],

        earlierRef: earlier ? more.earlierRef : current?.earlierRef,

        laterRef: earlier ? current?.laterRef : more.laterRef,
      );

      state = state.copyWith(result: combined, isLoading: false);
    } catch (e) {
      AppLog.log('loadMore failed: $e', tag: 'journey');

      state = state.copyWith(isLoading: false);
    }
  }

  String _journeyKey(Journey j) =>
      j.refreshToken ??
      '${j.departure?.toIso8601String()}|'
          '${j.arrival?.toIso8601String()}|'
          '${j.legs.firstOrNull?.line?.name ?? ''}';

  void clear() {
    state = JourneySearchState();
  }
}

final journeySearchProvider =
    NotifierProvider<JourneySearchNotifier, JourneySearchState>(
      JourneySearchNotifier.new,
    );

final journeyHighlightsProvider =
    Provider.autoDispose<Map<JourneyHighlight, Journey>>((ref) {
      final journeys = ref.watch(journeySearchProvider).sortedJourneys;

      return journeyHighlights(
        journeys,
        (j) => ref
            .watch(journeyPredictionProvider(PredictionRequest(j)))
            .asData
            ?.value
            ?.reliabilityScore,
      );
    });

final reliabilitySortedJourneysProvider = Provider.autoDispose<List<Journey>>((
  ref,
) {
  final state = ref.watch(journeySearchProvider);

  final journeys = state.sortedJourneys;

  if (state.sortMode != JourneySortMode.reliability) {
    return journeys;
  }

  final scored = <({Journey journey, double? score, int order})>[
    for (final (i, j) in journeys.indexed)
      (
        journey: j,

        score: ref
            .watch(journeyPredictionProvider(PredictionRequest(j)))
            .asData
            ?.value
            ?.reliabilityScore,

        order: i,
      ),
  ];

  scored.sort((a, b) {
    if (a.score == null && b.score == null) {
      return a.order.compareTo(b.order);
    }

    if (a.score == null) {
      return 1;
    }

    if (b.score == null) {
      return -1;
    }

    final score = b.score!.compareTo(a.score!);

    return score != 0 ? score : a.order.compareTo(b.order);
  });

  return [for (final item in scored) item.journey];
});
