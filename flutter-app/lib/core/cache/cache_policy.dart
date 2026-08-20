class CachePolicy {
  final Duration ttl;

  const CachePolicy({required this.ttl});

  static const journeySearch = CachePolicy(ttl: Duration(hours: 2));

  static const stationSearch = CachePolicy(ttl: Duration(days: 7));
}
