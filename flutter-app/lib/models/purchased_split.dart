/// One split-ticket the user confirms they actually bought (#70).
///
/// Only a confirmed purchase counts as "saved" — a merely computed saving would
/// inflate the total without the rider ever having pocketed the difference. So
/// this is written from an explicit "Ich habe das gekauft" tap, never
/// automatically from a split analysis.
class PurchasedSplit {
  /// Human-readable route, e.g. "Kiel → Hamburg" — for the list row.
  final String routeLabel;

  /// What the single through-ticket would have cost (DB direct price).
  final double directPrice;

  /// Sum of the split segments actually bought.
  final double splitPrice;

  /// When the user confirmed the purchase (epoch ms).
  final int purchasedAtMs;

  /// ISO departure of the trip the split was for, when known — lets us dedupe a
  /// double-tap on the same connection and show the travel date.
  final String? departureIso;

  const PurchasedSplit({
    required this.routeLabel,
    required this.directPrice,
    required this.splitPrice,
    required this.purchasedAtMs,
    this.departureIso,
  });

  /// Never negative: a split priced above the through-ticket saved nothing.
  double get savings {
    final diff = directPrice - splitPrice;
    return diff > 0 ? diff : 0;
  }

  /// Stable identity for dedupe — same route + same departure = same purchase.
  String get dedupeKey => '$routeLabel|${departureIso ?? ''}';

  Map<String, dynamic> toJson() => {
    'routeLabel': routeLabel,
    'directPrice': directPrice,
    'splitPrice': splitPrice,
    'purchasedAtMs': purchasedAtMs,
    if (departureIso != null) 'departureIso': departureIso,
  };

  factory PurchasedSplit.fromJson(Map<String, dynamic> json) => PurchasedSplit(
    routeLabel: json['routeLabel'] as String? ?? '',
    directPrice: (json['directPrice'] as num?)?.toDouble() ?? 0,
    splitPrice: (json['splitPrice'] as num?)?.toDouble() ?? 0,
    purchasedAtMs: (json['purchasedAtMs'] as num?)?.toInt() ?? 0,
    departureIso: json['departureIso'] as String?,
  );
}
