import 'station.dart';

/// The parts of DB's `reiseHin.wunsch` the rider gets to steer beyond "from,
/// to, when": how often they're willing to change, how much slack a change
/// needs, and a station the route has to touch (#19).
///
/// All three are enforced by the backend, so a constraint set here shrinks the
/// search itself instead of filtering holes into a list we already fetched.
/// The DB Navigator bundles the same fields into one `SearchOptions` model;
/// this mirrors that, with the transport-mode chips and "Nur D-Ticket" staying
/// where they are — they're one tap on the result list and don't need a sheet.
class SearchOptions {
  /// Cap on changes (`maxUmstiege`). Null = as many as DB likes, 0 = direct
  /// trains only. Verified: Köln→München with 0 returns 5 of 5 direct.
  final int? maxTransfers;

  /// Minimum slack per change (`minUmstiegsdauer`), in minutes. Null means the
  /// transfer profile decides — see [TransferProfile.minTransferMinutes].
  /// Set here it wins over the profile: an explicit number is an answer to
  /// "how long do *I* need", which is exactly what the profile guesses.
  final int? minTransferMinutes;

  /// A station the connection must pass through (`viaLocations`). "Passing"
  /// counts — the route may run through it without a change there.
  final Station? via;

  /// Minimum stay at [via] (its own `minUmstiegsdauer`), for breaking a trip
  /// rather than just routing it. Null = no extra requirement.
  final int? viaStayMinutes;

  const SearchOptions({
    this.maxTransfers,
    this.minTransferMinutes,
    this.via,
    this.viaStayMinutes,
  });

  bool get directOnly => maxTransfers == 0;

  /// How many options deviate from the default — drives the badge on the
  /// button, so a constrained search is never invisible.
  int get activeCount =>
      (maxTransfers != null ? 1 : 0) +
      (minTransferMinutes != null ? 1 : 0) +
      (via != null ? 1 : 0);

  bool get isDefault => activeCount == 0;

  /// `viaLocations` as the backend wants it, or null when no via is set.
  List<Map<String, dynamic>>? get viaLocationsJson => via == null
      ? null
      : [
          {
            'locationId': via!.vendoLocationId,
            if (viaStayMinutes != null) 'minUmstiegsdauer': viaStayMinutes,
          },
        ];

  /// Nulling a field needs an explicit flag — `copyWith(maxTransfers: null)`
  /// can't tell "leave it" from "clear it".
  SearchOptions copyWith({
    int? maxTransfers,
    int? minTransferMinutes,
    Station? via,
    int? viaStayMinutes,
    bool clearMaxTransfers = false,
    bool clearMinTransferMinutes = false,
    bool clearVia = false,
    bool clearViaStayMinutes = false,
  }) {
    return SearchOptions(
      maxTransfers: clearMaxTransfers
          ? null
          : (maxTransfers ?? this.maxTransfers),
      minTransferMinutes: clearMinTransferMinutes
          ? null
          : (minTransferMinutes ?? this.minTransferMinutes),
      via: clearVia ? null : (via ?? this.via),
      // A stay without a via is meaningless — clearing the via clears it too.
      viaStayMinutes: (clearVia || clearViaStayMinutes)
          ? null
          : (viaStayMinutes ?? this.viaStayMinutes),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SearchOptions &&
      other.maxTransfers == maxTransfers &&
      other.minTransferMinutes == minTransferMinutes &&
      other.via?.vendoLocationId == via?.vendoLocationId &&
      other.viaStayMinutes == viaStayMinutes;

  @override
  int get hashCode => Object.hash(
    maxTransfers,
    minTransferMinutes,
    via?.vendoLocationId,
    viaStayMinutes,
  );
}
