/// Which company actually runs a train — the thing DB's line label hides. An
/// erixx train shows as "RE 83" in DB's app, but it's operated by **erixx**;
/// this surfaces that (#operator).
///
/// The signal is the vendo `kurztext` (→ [TransitLine.productName]): private
/// operators carry their own short code there ("erx", "ME", …), while DB's own
/// runs use the generic product ("RE", "ICE"). So it's a curated code→operator
/// map plus a DB fallback by product. No network. The colour is a brand accent
/// for a small badge — a lightweight stand-in until real image logos are added.
library;

class TrainOperator {
  final String name;
  final int color; // ARGB brand accent
  const TrainOperator(this.name, this.color);
}

// Lower-cased short code → operator. Private EVUs (kurztext = their code) first.
const _byCode = <String, TrainOperator>{
  'erx': TrainOperator('erixx', 0xFF95C11F), // erixx lime green
  'me': TrainOperator('metronom', 0xFFFFD200), // metronom yellow
  'meno': TrainOperator('metronom', 0xFFFFD200),
  'nwb': TrainOperator('NordWestBahn', 0xFF005CA9),
  'nbe': TrainOperator('nordbahn', 0xFF00A5E3),
  'wfb': TrainOperator('WestfalenBahn', 0xFF00447C),
  'nx': TrainOperator('National Express', 0xFFE2001A),
  'flx': TrainOperator('FlixTrain', 0xFF73D700),
  'rt': TrainOperator('Regiobahn', 0xFF0069B4),
  'vias': TrainOperator('VIAS', 0xFF009EE0),
};

/// The operator for a line, or null when unknown.
TrainOperator? operatorFor({
  String? productName,
  String? product,
  String? name,
}) {
  final code = (productName ?? '').trim().toLowerCase();
  final byCode = _byCode[code];
  if (byCode != null) return byCode;
  // Some feeds carry the operator short in the name ("ERX 83", "ME 82").
  final head = (name ?? '').trim().toLowerCase().split(RegExp(r'[\s\d]')).first;
  if (head.isNotEmpty) {
    final byName = _byCode[head];
    if (byName != null) return byName;
  }
  // DB's own products.
  switch (product) {
    case 'nationalExpress':
    case 'national':
      return const TrainOperator('DB Fernverkehr', 0xFFEC0016);
    case 'regional':
    case 'suburban':
      return const TrainOperator('DB Regio', 0xFFEC0016);
  }
  return null;
}
