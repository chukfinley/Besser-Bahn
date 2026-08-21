import 'journey.dart';
import 'station.dart';

/// A station the user has searched for or starred. [pinned] means it shows in
/// the favorites list — set manually (tap star) or automatically once
/// [useCount] crosses the auto-star threshold. Even unpinned entries are kept
/// to power the "recents" suggestions.
class FavoriteStation {
  final Station station;
  final bool pinned;
  final int useCount;
  final int lastUsedMs;

  /// True if this entry was *only* added because we pulled the DB account's
  /// server-side favorites in. On logout we drop these so the search no longer
  /// shows suggestions tied to a signed-out account. Anything the user
  /// touched themselves (useCount > 0 or manually pinned) is treated as
  /// theirs even after the merge — it stays.
  final bool fromServer;

  const FavoriteStation({
    required this.station,
    this.pinned = false,
    this.useCount = 0,
    this.lastUsedMs = 0,
    this.fromServer = false,
  });

  FavoriteStation copyWith({
    bool? pinned,
    int? useCount,
    int? lastUsedMs,
    bool? fromServer,
  }) {
    return FavoriteStation(
      station: station,
      pinned: pinned ?? this.pinned,
      useCount: useCount ?? this.useCount,
      lastUsedMs: lastUsedMs ?? this.lastUsedMs,
      fromServer: fromServer ?? this.fromServer,
    );
  }

  Map<String, dynamic> toJson() => {
    'station': station.toJson(),
    'pinned': pinned,
    'useCount': useCount,
    'lastUsedMs': lastUsedMs,
    if (fromServer) 'fromServer': true,
  };

  factory FavoriteStation.fromJson(Map<String, dynamic> json) =>
      FavoriteStation(
        station: Station.fromJson(
          json['station'] as Map<String, dynamic>? ?? {},
        ),
        pinned: json['pinned'] as bool? ?? false,
        useCount: json['useCount'] as int? ?? 0,
        lastUsedMs: json['lastUsedMs'] as int? ?? 0,
        fromServer: json['fromServer'] as bool? ?? false,
      );
}

/// A saved origin→destination pair for one-tap re-search.
class SavedRoute {
  final Station from;
  final Station to;

  const SavedRoute({required this.from, required this.to});

  /// Stable identity, used for dedup and toggling.
  String get key => '${from.id}_${to.id}';

  Map<String, dynamic> toJson() => {'from': from.toJson(), 'to': to.toJson()};

  factory SavedRoute.fromJson(Map<String, dynamic> json) => SavedRoute(
    from: Station.fromJson(json['from'] as Map<String, dynamic>? ?? {}),
    to: Station.fromJson(json['to'] as Map<String, dynamic>? ?? {}),
  );
}

/// A saved train. [query] is what gets fed back into the train lookup (e.g.
/// "ICE 148"); [label] is the human-readable name shown on the chip.
class SavedTrain {
  final String query;
  final String label;
  final String? fromStationId;

  const SavedTrain({
    required this.query,
    required this.label,
    this.fromStationId,
  });

  String get key => fromStationId == null ? query : '$query@$fromStationId';

  Map<String, dynamic> toJson() => {
    'query': query,
    'label': label,
    'fromStationId': fromStationId,
  };

  factory SavedTrain.fromJson(Map<String, dynamic> json) => SavedTrain(
    query: json['query'] as String? ?? '',
    label: json['label'] as String? ?? '',
    fromStationId: json['fromStationId'] as String?,
  );
}

/// A whole connection the user bookmarked from the search/detail view — the
/// "Reisen" feature, like the official DB Navigator. We persist the full
/// [Journey] (legs, times, prices) plus when it was saved, and re-fetch live
/// data when opened. Trips whose arrival is in the past show under
/// "Vergangene Reisen" and are auto-purged after a grace period.
class SavedJourney {
  final Journey journey;
  final int savedAtMs;

  /// Whether the live companion may track THIS trip — poll its run and push
  /// delay/platform/cancellation/transfer alerts (#11, point 2).
  ///
  /// Requested as an explicitly-activated, per-trip mode on privacy grounds.
  /// Defaults to true, deliberately: tracking used to apply to every saved
  /// trip, so defaulting to false would silently take alerts away from people
  /// who already rely on them. Opt-in for the *feature* stays the global
  /// reminders switch; this is per-trip opt-OUT below it.
  final bool watched;

  const SavedJourney({
    required this.journey,
    required this.savedAtMs,
    this.watched = true,
  });

  SavedJourney copyWith({bool? watched}) => SavedJourney(
    journey: journey,
    savedAtMs: savedAtMs,
    watched: watched ?? this.watched,
  );

  /// Stable identity: origin→destination at the planned departure minute.
  /// Same train on the same day dedupes; tomorrow's run is its own entry.
  String get key {
    final dep = journey.plannedDeparture ?? journey.departure;
    final stamp = dep?.toIso8601String().substring(0, 16) ?? '';
    return '${journey.origin?.id ?? ''}_${journey.destination?.id ?? ''}_$stamp';
  }

  /// When the trip is considered over (its final arrival).
  DateTime? get endTime => journey.arrival ?? journey.plannedArrival;

  /// True once the connection's arrival lies in the past.
  bool get isPast {
    final end = endTime;
    return end != null && end.isBefore(DateTime.now());
  }

  Map<String, dynamic> toJson() => {
    'journey': journey.toJson(),
    'savedAtMs': savedAtMs,
    'watched': watched,
  };

  factory SavedJourney.fromJson(Map<String, dynamic> json) => SavedJourney(
    journey: Journey.fromJson(json['journey'] as Map<String, dynamic>? ?? {}),
    savedAtMs: json['savedAtMs'] as int? ?? 0,
    // Absent = saved before this existed → keep tracking it, so the update
    // doesn't quietly switch off alerts people already depend on.
    watched: json['watched'] as bool? ?? true,
  );
}
