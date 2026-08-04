/// Lifetime, on-device travel tally — the persisted half of the "Reise­statistik"
/// feature. Saved trips ([SavedJourney]) auto-purge a week after arrival, so we
/// can't derive lifetime totals from them; instead each completed trip is folded
/// into this accumulator exactly once (see TravelStatsNotifier) and kept
/// forever, locally, with no server in the loop.
///
/// CO₂ is intentionally absent: it's not reliably derivable client-side. The
/// official figure lives in the DB-Bonus app and will be fetched once real
/// Deutsche-Bahn login lands — until then the UI shows a placeholder row.
class TravelStats {
  /// Summed leg distance across all counted trips, in kilometres.
  final double totalKm;

  /// Number of completed trips counted.
  final int tripCount;

  /// Summed arrival delay (minutes) at each trip's final destination. Only
  /// positive delays add; an early/on-time arrival contributes 0.
  final int totalDelayMinutes;

  /// Trips that arrived "on time" by the DB definition (under 6 min late).
  final int onTimeCount;

  /// Worst single arrival delay seen, in minutes.
  final int worstDelayMinutes;

  /// Longest single trip, in kilometres.
  final double longestTripKm;

  /// Arrival time of the earliest counted trip — powers "seit Monat Jahr".
  /// 0 when nothing has been counted yet.
  final int firstTripMs;

  /// How often each "Origin → Destination" route was travelled — powers
  /// "häufigste Strecken" (#71).
  final Map<String, int> routeCounts;

  /// How often each transit line was ridden — powers "meistgenutzte Linien"
  /// (#71). One count per boarded leg.
  final Map<String, int> lineCounts;

  /// Total transfers across all counted trips (#71).
  final int connectionsTotal;

  /// Transfers that could not be made (feeder arrived after the onward train
  /// left, or the onward leg was cancelled). A conservative lower bound (#71).
  final int connectionsMissed;

  /// Per-route punctuality from your OWN completed trips (#63): route label →
  /// how many of those arrivals were on time. Counted against [routeCounts],
  /// so "4 von 6" needs both maps.
  ///
  /// Deliberately your observation, not a statistic about the line: it is the
  /// only reliability figure the app can state without a server, and it is the
  /// one the rider can check against their own memory.
  final Map<String, int> routeOnTime;

  const TravelStats({
    this.totalKm = 0,
    this.tripCount = 0,
    this.totalDelayMinutes = 0,
    this.onTimeCount = 0,
    this.worstDelayMinutes = 0,
    this.longestTripKm = 0,
    this.firstTripMs = 0,
    this.routeCounts = const {},
    this.lineCounts = const {},
    this.connectionsTotal = 0,
    this.connectionsMissed = 0,
    this.routeOnTime = const {},
  });

  static const empty = TravelStats();

  bool get isEmpty => tripCount == 0;

  /// Share of trips that arrived on time, 0‥1. 0 when no trips counted.
  double get onTimeRate => tripCount == 0 ? 0 : onTimeCount / tripCount;

  /// Average arrival delay per trip, in minutes.
  double get avgDelayMinutes =>
      tripCount == 0 ? 0 : totalDelayMinutes / tripCount;

  /// Transfers successfully made (total minus missed).
  int get connectionsMade {
    final made = connectionsTotal - connectionsMissed;
    return made > 0 ? made : 0;
  }

  /// The [n] most-travelled routes, most first, as (label, count).
  List<MapEntry<String, int>> topRoutes([int n = 3]) => _top(routeCounts, n);

  /// How your own trips on [route] went (#63), or null when you have not
  /// travelled it often enough to say anything.
  ///
  /// Three is the smallest number that can be wrong twice and still mean
  /// something; below that "1 von 1 pünktlich" reads as a claim about the
  /// route when it is a claim about one Tuesday.
  ({int trips, int onTime})? experienceOn(String route, {int minTrips = 3}) {
    final trips = routeCounts[route] ?? 0;
    if (trips < minTrips) return null;
    return (trips: trips, onTime: routeOnTime[route] ?? 0);
  }

  /// The [n] most-ridden lines, most first, as (label, count).
  List<MapEntry<String, int>> topLines([int n = 3]) => _top(lineCounts, n);

  static List<MapEntry<String, int>> _top(Map<String, int> m, int n) {
    final entries = m.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.take(n).toList();
  }

  TravelStats copyWith({
    double? totalKm,
    int? tripCount,
    int? totalDelayMinutes,
    int? onTimeCount,
    int? worstDelayMinutes,
    double? longestTripKm,
    int? firstTripMs,
    Map<String, int>? routeCounts,
    Map<String, int>? lineCounts,
    int? connectionsTotal,
    int? connectionsMissed,
    Map<String, int>? routeOnTime,
  }) {
    return TravelStats(
      totalKm: totalKm ?? this.totalKm,
      tripCount: tripCount ?? this.tripCount,
      totalDelayMinutes: totalDelayMinutes ?? this.totalDelayMinutes,
      onTimeCount: onTimeCount ?? this.onTimeCount,
      worstDelayMinutes: worstDelayMinutes ?? this.worstDelayMinutes,
      longestTripKm: longestTripKm ?? this.longestTripKm,
      firstTripMs: firstTripMs ?? this.firstTripMs,
      routeCounts: routeCounts ?? this.routeCounts,
      lineCounts: lineCounts ?? this.lineCounts,
      connectionsTotal: connectionsTotal ?? this.connectionsTotal,
      connectionsMissed: connectionsMissed ?? this.connectionsMissed,
      routeOnTime: routeOnTime ?? this.routeOnTime,
    );
  }

  Map<String, dynamic> toJson() => {
        'totalKm': totalKm,
        'tripCount': tripCount,
        'totalDelayMinutes': totalDelayMinutes,
        'onTimeCount': onTimeCount,
        'worstDelayMinutes': worstDelayMinutes,
        'longestTripKm': longestTripKm,
        'firstTripMs': firstTripMs,
        'routeCounts': routeCounts,
        'lineCounts': lineCounts,
        'connectionsTotal': connectionsTotal,
        'connectionsMissed': connectionsMissed,
        'routeOnTime': routeOnTime,
      };

  factory TravelStats.fromJson(Map<String, dynamic> json) => TravelStats(
        totalKm: (json['totalKm'] as num?)?.toDouble() ?? 0,
        tripCount: json['tripCount'] as int? ?? 0,
        totalDelayMinutes: json['totalDelayMinutes'] as int? ?? 0,
        onTimeCount: json['onTimeCount'] as int? ?? 0,
        worstDelayMinutes: json['worstDelayMinutes'] as int? ?? 0,
        longestTripKm: (json['longestTripKm'] as num?)?.toDouble() ?? 0,
        firstTripMs: json['firstTripMs'] as int? ?? 0,
        routeCounts: _intMap(json['routeCounts']),
        lineCounts: _intMap(json['lineCounts']),
        connectionsTotal: json['connectionsTotal'] as int? ?? 0,
        connectionsMissed: json['connectionsMissed'] as int? ?? 0,
        // Absent in stats saved before #63 — an old install simply starts
        // collecting from its next trip instead of losing its other numbers.
        routeOnTime: _intMap(json['routeOnTime']),
      );

  static Map<String, int> _intMap(dynamic raw) {
    if (raw is! Map) return const {};
    return raw.map((k, v) => MapEntry(k as String, (v as num).toInt()));
  }
}
