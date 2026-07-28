/// Rephrases Deutsche-Bahn disruption/running notes into plainer German (#74),
/// for riders who find the official wording hard to read. Conservative,
/// meaning-preserving substitutions only — it swaps well-known jargon for an
/// everyday equivalent, it never drops or invents information.
///
/// Applied only when the "Einfache Sprache" setting is on; the original text is
/// what's shown otherwise.
library;

/// Ordered jargon → plain replacements. Case-insensitive on the key, longest
/// first so "Schienenersatzverkehr" wins over "Ersatzverkehr". The replacement
/// keeps the sentence readable, not clipped.
const _replacements = <String, String>{
  'Schienenersatzverkehr': 'Ersatz-Bus statt Zug',
  'Ersatzverkehr': 'Ersatz-Bus',
  'Bauarbeiten': 'Baustelle',
  'Baumaßnahmen': 'Baustelle',
  'Baumaßnahme': 'Baustelle',
  'Streckensperrung': 'gesperrte Strecke',
  'aufgrund': 'wegen',
  'voraussichtlich': 'wahrscheinlich',
  'verkehrt': 'fährt',
  'entfällt': 'fällt aus',
  'Verzögerung': 'Verspätung',
  'Fahrtausfall': 'Zug fällt aus',
  'Umleitung': 'anderer Weg',
  'unregelmäßig': 'nicht nach Plan',
  'Weiterfahrt': 'Weiterreise',
  'Reisendeninformation': 'Info für Reisende',
};

/// Simplify a single note. Returns it unchanged when nothing matches.
String simplifyNote(String note) {
  var out = note;
  for (final entry in _replacements.entries) {
    out = out.replaceAll(
      RegExp(RegExp.escape(entry.key), caseSensitive: false),
      entry.value,
    );
  }
  return out;
}

/// Simplify [note] only when [enabled]; otherwise the original text.
String plainNote(String note, {required bool enabled}) =>
    enabled ? simplifyNote(note) : note;
