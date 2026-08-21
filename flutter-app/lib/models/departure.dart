import 'station.dart';

class Departure {
  final String tripId;
  final Station stop;
  final DateTime? when; // actual (with delay)
  final DateTime? plannedWhen; // scheduled
  final int? delay; // seconds
  final String? platform;
  final String? plannedPlatform;
  final String direction;
  final TransitLine line;
  final bool cancelled;
  final List<String> remarks;

  const Departure({
    required this.tripId,
    required this.stop,
    this.when,
    this.plannedWhen,
    this.delay,
    this.platform,
    this.plannedPlatform,
    required this.direction,
    required this.line,
    this.cancelled = false,
    this.remarks = const [],
  });

  bool get hasPlatformChange =>
      platform != null &&
      plannedPlatform != null &&
      platform != plannedPlatform;

  bool get isDelayed => delay != null && delay! > 0;

  int get delayMinutes => delay != null ? delay! ~/ 60 : 0;

  factory Departure.fromHafas(Map<String, dynamic> json) {
    final stopJson = json['stop'] as Map<String, dynamic>? ?? {};
    final lineJson = json['line'] as Map<String, dynamic>? ?? {};
    final remarksList = json['remarks'] as List<dynamic>? ?? [];

    return Departure(
      tripId: json['tripId'] as String? ?? '',
      stop: Station.fromHafas(stopJson),
      when: _parseDateTime(json['when']),
      plannedWhen: _parseDateTime(json['plannedWhen']),
      delay: json['delay'] as int?,
      platform: json['platform'] as String?,
      plannedPlatform: json['plannedPlatform'] as String?,
      direction: json['direction'] as String? ?? '',
      line: TransitLine.fromHafas(lineJson),
      cancelled: json['cancelled'] as bool? ?? false,
      remarks: remarksList
          .whereType<Map<String, dynamic>>()
          .map((r) => r['text'] as String? ?? r['summary'] as String? ?? '')
          .where((s) => s.isNotEmpty)
          .toList(),
    );
  }
}

class TransitLine {
  final String name;
  final String fahrtNr;
  final String productName; // ICE, IC, RE, S, etc.
  final String product; // nationalExpress, national, etc.
  final String? operatorName;

  const TransitLine({
    required this.name,
    required this.fahrtNr,
    required this.productName,
    required this.product,
    this.operatorName,
  });

  factory TransitLine.fromHafas(Map<String, dynamic> json) {
    final op = json['operator'] as Map<String, dynamic>?;
    return TransitLine(
      name: json['name'] as String? ?? '',
      fahrtNr: json['fahrtNr'] as String? ?? '',
      productName: json['productName'] as String? ?? '',
      product: json['product'] as String? ?? '',
      operatorName: op?['name'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'fahrtNr': fahrtNr,
    'productName': productName,
    'product': product,
    'operatorName': operatorName,
  };

  factory TransitLine.fromJson(Map<String, dynamic> json) => TransitLine(
    name: json['name'] as String? ?? '',
    fahrtNr: json['fahrtNr'] as String? ?? '',
    productName: json['productName'] as String? ?? '',
    product: json['product'] as String? ?? '',
    operatorName: json['operatorName'] as String?,
  );

  /// Returns short display name like "ICE 148" or "RE 1"
  String get displayName {
    if (name.isNotEmpty) return name;
    if (productName.isNotEmpty && fahrtNr.isNotEmpty) {
      return '$productName $fahrtNr';
    }
    return fahrtNr;
  }

  /// The line label with the product letters spaced from the line digits,
  /// e.g. "RE7" → "RE 7", "S1" → "S 1", "ICE" stays "ICE".
  String get lineLabel {
    final n = name.trim();
    if (n.isEmpty) return productName;
    return n.replaceFirstMapped(
      RegExp(r'^([A-Za-zÄÖÜäöü]+)\s*(\d)'),
      (m) => '${m[1]} ${m[2]}',
    );
  }

  /// Header title: the line plus the official train number in parentheses when
  /// it adds information — e.g. "RE 7 (11281)". Long-distance lines whose label
  /// already *is* the running number collapse to just the label ("ICE 571").
  String get titleWithNumber {
    final label = lineLabel;
    final nr = fahrtNr.trim();
    if (nr.isEmpty || label.contains(nr)) return label;
    return '$label ($nr)';
  }

  /// Just the line's running number/identifier, with the product prefix
  /// stripped — "RE7" → "7", "ICE 571" → "571", "S 1" → "1". Used next to the
  /// product badge so the product ("RE") isn't shown twice. Falls back to the
  /// full label/number when there's no alphabetic prefix to strip.
  String get lineNumber {
    final n = name.trim();
    if (n.isNotEmpty) {
      final m = RegExp(r'^[A-Za-zÄÖÜäöü]+\s*(.+)$').firstMatch(n);
      if (m != null) return m.group(1)!.trim();
      return n;
    }
    return fahrtNr;
  }

  /// Line number with the official train number in parentheses when it adds
  /// info — "7 (11281)". Product stays in the badge; this is what sits next to
  /// it. Collapses to the bare number when the fahrtNr is the same or absent.
  String get lineNumberWithFahrt {
    final base = lineNumber;
    final nr = fahrtNr.trim();
    if (nr.isEmpty || base == nr || base.contains(nr)) return base;
    return '$base ($nr)';
  }

  /// Short product code for the circled badge — ALWAYS non-empty for a real
  /// service, so non-DB operators (ÖBB "RJX", Flixtrain "FLX", a Fernbus) get a
  /// badge too, not just RE/ICE. Prefers the explicit product short text, else
  /// the alphabetic prefix of the line name ("RJX 69" → "RJX"), else a generic
  /// label from the coarse product class ("BUS", "U", "S", …).
  String get productBadge {
    final pn = productName.trim();
    if (pn.isNotEmpty) return pn.toUpperCase();
    final m = RegExp(r'^([A-Za-zÄÖÜäöü]{1,5})').firstMatch(name.trim());
    if (m != null) return m.group(1)!.toUpperCase();
    return switch (product) {
      'nationalExpress' => 'ICE',
      'national' => 'IC',
      'regional' => 'RB',
      'suburban' => 'S',
      'subway' => 'U',
      'tram' => 'STR',
      'bus' => 'BUS',
      'ferry' => 'FÄHRE',
      _ => 'ZUG',
    };
  }

  /// Same line but with a different label (the real line, e.g. "RE7"), carried
  /// over from a departure/leg into a freshly fetched trip whose API omits it.
  TransitLine withName(String newName) => TransitLine(
    name: newName,
    fahrtNr: fahrtNr,
    productName: productName,
    product: product,
    operatorName: operatorName,
  );
}

DateTime? _parseDateTime(dynamic value) {
  if (value == null) return null;
  if (value is String) return DateTime.tryParse(value);
  return null;
}
