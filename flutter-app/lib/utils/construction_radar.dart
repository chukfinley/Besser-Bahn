/// Recognises the long-term, construction-driven disruption notes DB puts in a
/// connection's HIM messages — the ones worth surfacing days ahead for a saved
/// route (#62), as opposed to a today-only delay ("5 Minuten später").
///
/// Pure string matching on the German notes, so it's testable without the
/// network. Deliberately conservative: it keys off the words DB uses for
/// planned engineering work / replacement service / line closures, not on
/// realtime running notes.
library;

/// Words that mark a note as a planned/construction disruption. Lower-cased
/// substrings — matched against a lower-cased note.
const _kConstructionMarkers = <String>[
  'bauarbeit', // Bauarbeiten, Bauarbeit
  'baumaßnahme',
  'baumassnahme',
  'baustelle',
  'ersatzverkehr', // (Schienen-)Ersatzverkehr
  'schienenersatz',
  'busnotverkehr',
  'streckensperr', // Streckensperrung
  'gesperrt',
  'umleitung',
  'umgeleitet',
  'baubedingt',
];

/// True when [note] reads like a construction / long-term disruption.
bool isConstructionNote(String note) {
  final n = note.toLowerCase();
  return _kConstructionMarkers.any(n.contains);
}

/// The construction-related notes among [notes], de-duplicated, order kept.
List<String> constructionNotes(Iterable<String> notes) {
  final seen = <String>{};
  final out = <String>[];
  for (final note in notes) {
    final t = note.trim();
    if (t.isEmpty || !isConstructionNote(t)) continue;
    if (seen.add(t)) out.add(t);
  }
  return out;
}
