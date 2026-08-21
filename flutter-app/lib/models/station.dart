/// What a search hit actually is. DB's location search answers with stops
/// (`ST`), house addresses (`ADR`) and points of interest (`POI`) — the journey
/// API takes all three as origin/destination and fills in the footpath, but
/// only a stop has an EVA number (so only a stop has a departure board or a
/// station map).
enum LocationKind {
  station,
  address,
  poi;

  static LocationKind fromVendo(String? type) => switch (type) {
    'ADR' => LocationKind.address,
    'POI' => LocationKind.poi,
    _ => LocationKind.station,
  };

  static LocationKind fromName(String? name) => LocationKind.values.firstWhere(
    (k) => k.name == name,
    orElse: () => LocationKind.station,
  );

  /// German label for the suggestion list.
  String get label => switch (this) {
    LocationKind.station => 'Haltestelle',
    LocationKind.address => 'Adresse',
    LocationKind.poi => 'Ort',
  };
}

class Station {
  final String id; // EVA number (stops only — empty for addresses/POIs)
  final String name;
  final double? latitude;
  final double? longitude;
  final StationProducts? products;

  /// Full HAFAS location string (`A=1@O=...@L=<eva>@...`). Required by the
  /// DB Vendo journey API; the plain EVA [id] is not enough there.
  final String? locationId;

  /// Stop, address or POI — see [LocationKind]. Everything that needs an EVA
  /// (departure board, station map, Wagenreihung) must check [isStop] first.
  final LocationKind kind;

  const Station({
    required this.id,
    required this.name,
    this.latitude,
    this.longitude,
    this.products,
    this.locationId,
    this.kind = LocationKind.station,
  });

  /// True for a real stop, i.e. something with an EVA and a board behind it.
  bool get isStop => kind == LocationKind.station;

  factory Station.fromHafas(Map<String, dynamic> json) {
    final loc = json['location'] as Map<String, dynamic>?;
    final prods = json['products'] as Map<String, dynamic>?;
    return Station(
      id: (json['id'] ?? json['extId'] ?? '').toString(),
      name: json['name'] as String? ?? '',
      latitude: loc?['latitude'] as double? ?? json['lat'] as double?,
      longitude: loc?['longitude'] as double? ?? json['lon'] as double?,
      products: prods != null ? StationProducts.fromJson(prods) : null,
    );
  }

  factory Station.fromDbWeb(Map<String, dynamic> json) {
    // bahn.de `reiseloesung/orte` returns `id` = full HAFAS string,
    // `extId` = EVA number. Keep both.
    final full = json['id']?.toString();
    return Station(
      id: (json['extId'] ?? json['id'] ?? '').toString(),
      name: json['name'] as String? ?? '',
      latitude: json['lat'] as double?,
      longitude: json['lon'] as double?,
      locationId: (full != null && full.contains('@')) ? full : null,
    );
  }

  /// Compact JSON for local persistence (favorites, recents, saved routes).
  /// [products] is intentionally dropped — not needed for stored stations.
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'lat': latitude,
    'lon': longitude,
    'locationId': locationId,
    // Only written for non-stops, so stored favorites from older versions
    // (and every stop) keep reading back as a station.
    if (kind != LocationKind.station) 'kind': kind.name,
  };

  factory Station.fromJson(Map<String, dynamic> json) => Station(
    id: json['id']?.toString() ?? '',
    name: json['name'] as String? ?? '',
    latitude: (json['lat'] as num?)?.toDouble(),
    longitude: (json['lon'] as num?)?.toDouble(),
    locationId: json['locationId'] as String?,
    kind: LocationKind.fromName(json['kind'] as String?),
  );

  bool get hasLocation => latitude != null && longitude != null;

  /// Best identifier for the DB Vendo journey API: the full HAFAS string if we
  /// have it, otherwise a minimal one built from the EVA number. An address or
  /// POI has no EVA, so `A=1@L=…` must never be synthesised for one — its
  /// locationId is the only handle the backend accepts.
  String get vendoLocationId =>
      locationId ?? (isStop && id.isNotEmpty ? 'A=1@L=$id@' : '');
}

class StationProducts {
  final bool nationalExpress; // ICE
  final bool national; // IC/EC
  final bool regionalExpress;
  final bool regional;
  final bool suburban; // S-Bahn
  final bool bus;
  final bool ferry;
  final bool subway; // U-Bahn
  final bool tram;

  const StationProducts({
    this.nationalExpress = false,
    this.national = false,
    this.regionalExpress = false,
    this.regional = false,
    this.suburban = false,
    this.bus = false,
    this.ferry = false,
    this.subway = false,
    this.tram = false,
  });

  factory StationProducts.fromJson(Map<String, dynamic> json) {
    return StationProducts(
      nationalExpress: json['nationalExpress'] as bool? ?? false,
      national: json['national'] as bool? ?? false,
      regionalExpress: json['regionalExpress'] as bool? ?? false,
      regional: json['regional'] as bool? ?? false,
      suburban: json['suburban'] as bool? ?? false,
      bus: json['bus'] as bool? ?? false,
      ferry: json['ferry'] as bool? ?? false,
      subway: json['subway'] as bool? ?? false,
      tram: json['tram'] as bool? ?? false,
    );
  }
}
