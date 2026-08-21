import '../core/api_client.dart';
import '../core/constants.dart';
import '../models/coach_sequence.dart';
import 'offline_store.dart';

/// Service for the Deutsche Bahn Wagenreihung (coach sequence) API
class CoachSequenceService {
  final ApiClient _client = ApiClient();
  static const _base = ApiConstants.dbWebApiBaseUrl;

  /// Session cache of resolved sequences, keyed by train + station + time, so a
  /// stop's platform train is drawn instantly once fetched and a whole trip's
  /// stops can be prefetched and kept warm while the journey is open.
  static final Map<String, CoachSequence> _cache = {};

  /// Get coach sequence for a train at a specific station
  ///
  /// [category] - Train category: ICE, IC, EC, etc.
  /// [number] - Train number (e.g., 148)
  /// [stationEva] - Station EVA number
  /// [date] - SERVICE date of the run — the one selector that matters (#32)
  /// [time] - Time of day at the station (ISO 8601). Measured to be ignored by
  ///   the endpoint; pass the scheduled time anyway so [date] stays the
  ///   timetable's service date.
  Future<CoachSequence> getCoachSequence({
    required String category,
    required int number,
    required String stationEva,
    required DateTime date,
    required DateTime time,
  }) async {
    final raw = await getCoachSequenceRaw(
      category: category,
      number: number,
      stationEva: stationEva,
      date: date,
      time: time,
    );
    return CoachSequence.fromJson(raw);
  }

  /// The raw vehicle-sequence response, before parsing.
  ///
  /// Exists so the offline package (#29) can persist the backend's own JSON and
  /// replay it through [CoachSequence.fromJson] with no network. [CoachSequence]
  /// has no `toJson`, and giving it one would mean keeping a second
  /// serialisation in step with the parser forever — storing the raw payload
  /// avoids that entirely.
  Future<Map<String, dynamic>> getCoachSequenceRaw({
    required String category,
    required int number,
    required String stationEva,
    required DateTime date,
    required DateTime time,
  }) async {
    final dateStr =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final timeStr = time.toUtc().toIso8601String();

    return await _client.get(
      '$_base/reisebegleitung/wagenreihung/vehicle-sequence',
      queryParams: {
        'administrationId': '80',
        'category': category,
        'date': dateStr,
        'evaNumber': stationEva,
        'number': number.toString(),
        'time': timeStr,
      },
    );
  }

  /// Normalise a leg's product + train number the way the vehicle-sequence
  /// endpoint expects, or null when this train has no sequence to fetch
  /// (bus/tram/U-Bahn, or an unparseable number). Shared so the offline package
  /// decides "is there a Wagenreihung here at all?" by exactly the same rule the
  /// live fetch uses — otherwise a package would report a part as missing that
  /// was never fetchable.
  static ({String category, int number})? sequenceKeyFor(
    String category,
    String trainNumber,
  ) {
    final cat = category.toUpperCase().trim();
    final number = int.tryParse(trainNumber.trim());
    if (number == null || !_coachCategories.contains(cat)) return null;
    return (category: cat, number: number);
  }

  /// The session/offline cache key for one train at one stop. Single definition
  /// so the live cache, the offline package and the offline replay can never
  /// disagree about what identifies a Wagenreihung.
  static String cacheKeyFor({
    required String category,
    required int number,
    required String stationEva,
    required DateTime departureTime,
  }) =>
      '$category|$number|$stationEva|${departureTime.toUtc().toIso8601String()}';

  /// Seed the session cache from a persisted payload, so an offline package's
  /// Wagenreihung is served exactly like a freshly fetched one.
  void seedFromRaw({
    required String category,
    required String trainNumber,
    required String stationEva,
    required DateTime departureTime,
    required Map<String, dynamic> raw,
  }) {
    final seq = sequenceKeyFor(category, trainNumber);
    if (seq == null) return;
    try {
      _cache[cacheKeyFor(
        category: seq.category,
        number: seq.number,
        stationEva: stationEva,
        departureTime: departureTime,
      )] = CoachSequence.fromJson(
        raw,
      );
    } catch (_) {
      // A payload we can't parse is simply not seeded; the caller's package
      // state already reflects what's actually on disk.
    }
  }

  /// Categories the vehicle-sequence endpoint actually serves. Long-distance
  /// (ICE/IC/EC) *and* the regional trains (RE/RB/IRE) — the latter matters for
  /// wing trains (Flügelzüge, e.g. the RE7 that splits in Neumünster into a Kiel
  /// and a Flensburg portion): the Wagenreihung is the only source that says
  /// *which* coaches go where.
  ///
  /// `S` is in the list despite the old "S-Bahn has no sequence" rule, which was
  /// simply wrong (#33). Measured over 9 networks (3 departures each, real
  /// endpoint, not DB's own board flag — that flag claims a Wagenreihung for
  /// München/Stuttgart/Frankfurt and then 404s): it is per-NETWORK and
  /// all-or-nothing, not random.
  ///
  ///   served 3/3  Rhein-Neckar (Heidelberg), Rhein-Ruhr (Essen),
  ///               Nürnberg, Dresden          → real cars, metres and sectors
  ///   served 0/3  Hamburg, Berlin, München, Stuttgart, Rhein-Main → 404
  ///
  /// So roughly half of all S-Bahn departures carry one, and where a network
  /// doesn't, the endpoint 404s and the app stays quiet exactly as it already
  /// does for a regional train's terminus. Worth having: the Rhein-Neckar S-Bahn
  /// even splits (S1 Homburg / S3 Germersheim portions coupled together), which
  /// is precisely the "which portion do I board" case this data exists for.
  ///
  /// Bus / tram / U-Bahn have no sequence → still skipped.
  static const _coachCategories = {
    'ICE',
    'IC',
    'EC',
    'ECE',
    'RE',
    'RB',
    'IRE',
    'RJ',
    'RJX',
    'EN',
    'NJ',
    'D',
    'S',
  };

  /// Get coach sequence for a train portion.
  ///
  /// [category] - product (ICE, IC, RE, RB, S, …).
  /// [trainNumber] - the *train* number (Zugnummer / fahrtNr, e.g. "11266"),
  ///   NOT the line number — a wing train's two portions share the line "RE 7"
  ///   but carry distinct train numbers.
  /// [departureTime] - the SCHEDULED time at this stop, not the live one.
  ///
  /// WHY SCHEDULED (#32). Measured against the live endpoint: the run is
  /// selected by `date` + category + number + evaNumber, and `time` is ignored
  /// outright — ICE 205 @ Köln Hbf answered with a byte-identical body for
  /// every time from −12 h to +12 h as long as `date` stayed the service date.
  /// So a delay does NOT break the lookup the way it looks like it should…
  /// except across midnight: [date] is derived from this very DateTime, so a
  /// live departure that slips past 00:00 rolls it onto the NEXT service date
  /// and 404s (verified: same train, date+1 → 404). The scheduled time keeps
  /// the run on its own date, and for a punctual train the two are identical —
  /// which also makes every caller's cache key agree instead of splitting into
  /// a planned-keyed and a live-keyed copy of the same sequence.
  Future<CoachSequence?> getCoachSequenceForDeparture({
    required String category,
    required String trainNumber,
    required String stationEva,
    required DateTime? departureTime,
  }) async {
    if (departureTime == null) return null;

    final seq = sequenceKeyFor(category, trainNumber);
    if (seq == null) return null;

    final key = cacheKeyFor(
      category: seq.category,
      number: seq.number,
      stationEva: stationEva,
      departureTime: departureTime,
    );
    final cached = _cache[key];
    if (cached != null) return cached;

    try {
      final cs = await getCoachSequence(
        category: seq.category,
        number: seq.number,
        stationEva: stationEva,
        date: departureTime,
        time: departureTime,
      );
      _cache[key] = cs;
      return cs;
    } catch (_) {
      // Network is gone (or DB is refusing) — fall back to an offline package's
      // copy if the rider downloaded one. Better a Wagenreihung from this
      // morning than none at all on the platform; the screen states its age.
      final raw = await OfflineStore.instance.readCoach(key);
      if (raw != null) {
        try {
          final cs = CoachSequence.fromJson(raw);
          _cache[key] = cs;
          return cs;
        } catch (_) {
          /* unusable payload → same as no data */
        }
      }
      return null;
    }
  }

  /// The already-resolved sequence for this train at this stop, if it's in the
  /// session cache (e.g. warmed by [prefetchTrainStops]) — else null. Lets the
  /// route map read a stop's parked train from the warm cache synchronously,
  /// without re-triggering a fetch on every rebuild.
  CoachSequence? cachedForDeparture({
    required String category,
    required String trainNumber,
    required String stationEva,
    required DateTime? departureTime,
  }) {
    if (departureTime == null) return null;
    final seq = sequenceKeyFor(category, trainNumber);
    if (seq == null) return null;
    return _cache[cacheKeyFor(
      category: seq.category,
      number: seq.number,
      stationEva: stationEva,
      departureTime: departureTime,
    )];
  }

  /// Warm the cache for every stop of one train (fire-and-forget) so opening any
  /// stop's platform map shows the to-scale train instantly — and it stays
  /// cached for the whole session while the journey is open.
  Future<void> prefetchTrainStops({
    required String category,
    required String trainNumber,
    required Iterable<({String eva, DateTime? time})> stops,
  }) async {
    // SEQUENTIAL, one request in flight at a time. The old `Future.wait` fired
    // every stop's vehicle-sequence call at once; on a long route that burst
    // of requests timed out en masse and janked the device.
    for (final s in stops) {
      if (s.eva.isEmpty || s.time == null) continue;
      await getCoachSequenceForDeparture(
        category: category,
        trainNumber: trainNumber,
        stationEva: s.eva,
        departureTime: s.time,
      );
    }
  }
}
